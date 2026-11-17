import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class RadioPlayerService: ObservableObject, PlaybackControlling {
    static let shared = RadioPlayerService()

    @Published private(set) var state: SharedPlayerState

    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "RadioPlayerService")
    private let engine: RadioPlaybackEngine
    private let stateStore: SharedPlayerStateStoring
    private let widgetReloader: WidgetReloading
    private let metadataService: NTSLiveMetadataFetching
    private var pendingStation: Station?
    private let metadataRefreshInterval: Duration
    private var metadataRefreshTask: Task<Void, Never>?

    init(
        engine: RadioPlaybackEngine = AVPlayerEngine(),
        stateStore: SharedPlayerStateStoring = SharedPlayerStateFileStore(),
        widgetReloader: WidgetReloading = WidgetReloader(),
        metadataService: NTSLiveMetadataFetching = NTSLiveMetadataService(),
        metadataRefreshInterval: Duration = .seconds(120),
        initialState: SharedPlayerState? = nil
    ) {
        self.engine = engine
        self.stateStore = stateStore
        self.widgetReloader = widgetReloader
        self.metadataService = metadataService
        self.metadataRefreshInterval = metadataRefreshInterval
        self.state = RadioPlayerService.launchState(
            initialState: initialState,
            stateStore: stateStore,
            engine: engine
        )

        self.engine.onStateChange = { [weak self] engineState in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.handleEngineState(engineState)
            }
        }
    }

    private static func launchState(
        initialState: SharedPlayerState?,
        stateStore: SharedPlayerStateStoring,
        engine: RadioPlaybackEngine
    ) -> SharedPlayerState {
        if let initialState {
            return initialState
        }

        let persistedState = stateStore.load()
        guard persistedState.isPlaying else {
            return persistedState
        }

        engine.pause()
        var pausedState = persistedState
        pausedState.isPlaying = false
        pausedState.statusText = "Paused"
        pausedState.lastError = nil
        pausedState.updatedAt = .now
        stateStore.save(pausedState)
        return pausedState
    }

    func play(station: Station) async throws -> SharedPlayerState {
        logger.log("play requested station=\(station.rawValue, privacy: .public)")
        pendingStation = station

        // Write the Connecting state up-front so the widget gets instant
        // feedback even before the engine callback arrives. Subsequent
        // engine `.connecting` callbacks will dedupe against this state.
        applyWithMetadata(
            currentStation: station,
            isPlaying: true,
            statusText: "Connecting \(station.displayName)",
            lastError: nil
        )

        do {
            try engine.load(url: station.streamURL)
            try engine.play()
        } catch {
            return transitionToError(error)
        }

        return state
    }

    func togglePlayback() async throws -> SharedPlayerState {
        let wasPlaying = state.isPlaying
        logger.log("togglePlayback requested wasPlaying=\(wasPlaying, privacy: .public)")

        if state.isPlaying {
            engine.pause()
            stopMetadataRefresh()

            applyWithMetadata(
                currentStation: state.currentStation,
                isPlaying: false,
                statusText: "Paused",
                lastError: nil
            )
            return state
        }

        let station = state.currentStation ?? .nts1
        return try await play(station: station)
    }

    func currentState() -> SharedPlayerState {
        state
    }

    private func handleEngineState(_ engineState: RadioEngineState) {
        logger.log("engine state=\(String(describing: engineState), privacy: .public)")

        switch engineState {
        case .idle:
            return
        case .connecting:
            let station = pendingStation ?? state.currentStation
            applyWithMetadata(
                currentStation: station,
                isPlaying: true,
                statusText: station.map { "Connecting \($0.displayName)" } ?? "Connecting",
                lastError: nil
            )
        case .playing:
            let station = pendingStation ?? state.currentStation
            applyWithMetadata(
                currentStation: station,
                isPlaying: true,
                statusText: station.map { "Playing \($0.displayName)" } ?? "Playing",
                lastError: nil
            )
            startMetadataRefresh()
        case .paused:
            stopMetadataRefresh()
            if !state.isPlaying, (state.lastError ?? "").isEmpty == false {
                return
            }

            applyWithMetadata(
                currentStation: state.currentStation,
                isPlaying: false,
                statusText: "Paused",
                lastError: nil
            )
        case .failed(let message):
            stopMetadataRefresh()
            applyWithMetadata(
                currentStation: state.currentStation,
                isPlaying: false,
                statusText: "Unavailable",
                lastError: message
            )
        }
    }

    private func transitionToError(_ error: Error) -> SharedPlayerState {
        stopMetadataRefresh()
        logger.error("transitionToError message=\(error.localizedDescription, privacy: .public)")

        applyWithMetadata(
            currentStation: state.currentStation,
            isPlaying: false,
            statusText: "Unavailable",
            lastError: error.localizedDescription
        )
        return state
    }

    /// Apply a new state: dedupe equivalent consecutive states, persist, and
    /// fire exactly one widget reload per meaningful transition. Chronod
    /// budgets widget reloads - firing many in quick succession causes later
    /// provider runs to be delayed.
    private func apply(_ newState: SharedPlayerState) {
        if isEquivalent(state, newState) {
            logger.log("apply skipped (state unchanged) isPlaying=\(newState.isPlaying, privacy: .public) status=\(newState.statusText, privacy: .public)")
            return
        }

        state = newState
        stateStore.save(newState)
        widgetReloader.reloadTimelines()
    }

    /// Ignore `updatedAt` so a pure timestamp churn doesn't trigger redundant
    /// keychain writes and widget reloads.
    private func isEquivalent(_ lhs: SharedPlayerState, _ rhs: SharedPlayerState) -> Bool {
        return lhs.currentStation == rhs.currentStation
            && lhs.isPlaying == rhs.isPlaying
            && lhs.statusText == rhs.statusText
            && (lhs.lastError ?? "") == (rhs.lastError ?? "")
            && lhs.nts1NowTitle == rhs.nts1NowTitle
            && lhs.nts2NowTitle == rhs.nts2NowTitle
            && lhs.metadataUpdatedAt == rhs.metadataUpdatedAt
    }

    private func applyWithMetadata(
        currentStation: Station?,
        isPlaying: Bool,
        statusText: String,
        lastError: String?
    ) {
        let newState = SharedPlayerState(
            currentStation: currentStation,
            isPlaying: isPlaying,
            statusText: statusText,
            lastError: lastError,
            updatedAt: .now,
            nts1NowTitle: state.nts1NowTitle,
            nts2NowTitle: state.nts2NowTitle,
            metadataUpdatedAt: state.metadataUpdatedAt
        )
        apply(newState)
    }

    /// Keeps the show titles current for as long as audio is playing.
    ///
    /// A single fetch at playback start is not enough: NTS changes shows on
    /// the hour, so a stream left running would keep showing the show it
    /// started on. `mergeMetadata` only persists (and reloads the widget) when
    /// a title actually changed, so polling does not burn chronod's reload
    /// budget. Runs only in the host, never in the widget extension.
    private func startMetadataRefresh() {
        metadataRefreshTask?.cancel()
        let service = metadataService
        let interval = metadataRefreshInterval
        // A failed fetch (typically the first one, racing stream start-up)
        // is retried soon rather than leaving a stale title for a full interval.
        let retryInterval = min(interval, .seconds(15))
        metadataRefreshTask = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                var delay = interval
                do {
                    let nowPlaying = try await service.fetchNowPlaying()
                    guard !Task.isCancelled else { return }
                    self?.mergeMetadata(nowPlaying)
                } catch {
                    delay = retryInterval
                    self?.logger.error("metadata fetch failed error=\(error.localizedDescription, privacy: .public)")
                }

                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
        }
    }

    private func stopMetadataRefresh() {
        metadataRefreshTask?.cancel()
        metadataRefreshTask = nil
    }

    @MainActor
    private func mergeMetadata(_ nowPlaying: NTSNowPlaying) {
        let updated = state.merged(with: nowPlaying)
        guard updated != state else {
            return
        }

        apply(updated)
    }
}
