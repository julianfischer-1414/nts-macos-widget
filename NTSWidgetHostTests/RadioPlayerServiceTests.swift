import XCTest
@testable import NTSWidgetHost

final class RadioPlayerServiceTests: XCTestCase {
    @MainActor
    func testIdleToPlayNTS1() async throws {
        let engine = MockRadioPlaybackEngine()
        let store = InMemorySharedPlayerStateStore(initialState: .idle())
        let reloader = MockWidgetReloader()
        let sut = RadioPlayerService(
            engine: engine,
            stateStore: store,
            widgetReloader: reloader,
            initialState: .idle()
        )

        // `play` reports Connecting synchronously so the widget gets immediate
        // feedback; Playing only arrives once the engine confirms it.
        let connecting = try await sut.play(station: .nts1)

        XCTAssertEqual(connecting.currentStation, .nts1)
        XCTAssertEqual(connecting.statusText, "Connecting NTS 1")
        XCTAssertEqual(engine.loadedURLs.last, Station.nts1.streamURL)
        XCTAssertEqual(engine.playCallCount, 1)
        XCTAssertEqual(reloader.reloadCallCount, 1)

        await simulateAndDrain(engine, .playing)

        XCTAssertEqual(sut.currentState().currentStation, .nts1)
        XCTAssertTrue(sut.currentState().isPlaying)
        XCTAssertEqual(sut.currentState().statusText, "Playing NTS 1")
        XCTAssertEqual(reloader.reloadCallCount, 2)
    }

    @MainActor
    func testSwitchFromNTS1ToNTS2() async throws {
        let engine = MockRadioPlaybackEngine()
        let store = InMemorySharedPlayerStateStore(initialState: .idle())
        let reloader = MockWidgetReloader()
        let sut = RadioPlayerService(
            engine: engine,
            stateStore: store,
            widgetReloader: reloader,
            initialState: .idle()
        )

        _ = try await sut.play(station: .nts1)
        await simulateAndDrain(engine, .playing)
        _ = try await sut.play(station: .nts2)
        await simulateAndDrain(engine, .playing)

        let state = sut.currentState()
        XCTAssertEqual(state.currentStation, .nts2)
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.statusText, "Playing NTS 2")
        XCTAssertEqual(engine.loadedURLs, [Station.nts1.streamURL, Station.nts2.streamURL])
    }

    @MainActor
    func testPlayingToPaused() async throws {
        let engine = MockRadioPlaybackEngine()
        let store = InMemorySharedPlayerStateStore(initialState: .idle())
        let reloader = MockWidgetReloader()
        let sut = RadioPlayerService(
            engine: engine,
            stateStore: store,
            widgetReloader: reloader,
            initialState: .idle()
        )

        _ = try await sut.play(station: .nts1)
        let paused = try await sut.togglePlayback()

        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.statusText, "Paused")
        XCTAssertEqual(paused.currentStation, .nts1)
        XCTAssertEqual(engine.pauseCallCount, 1)
    }

    @MainActor
    func testPausedToResumed() async throws {
        let engine = MockRadioPlaybackEngine()
        let store = InMemorySharedPlayerStateStore(initialState: .idle())
        let reloader = MockWidgetReloader()
        let sut = RadioPlayerService(
            engine: engine,
            stateStore: store,
            widgetReloader: reloader,
            initialState: .idle()
        )

        _ = try await sut.play(station: .nts1)
        await simulateAndDrain(engine, .playing)
        _ = try await sut.togglePlayback()
        _ = try await sut.togglePlayback()
        await simulateAndDrain(engine, .playing)

        let resumed = sut.currentState()
        XCTAssertTrue(resumed.isPlaying)
        XCTAssertEqual(resumed.currentStation, .nts1)
        XCTAssertEqual(resumed.statusText, "Playing NTS 1")
        XCTAssertEqual(engine.playCallCount, 2)
    }

    @MainActor
    func testLaunchDoesNotAutoplayPersistedPlayingState() async throws {
        let persistedPlayingState = SharedPlayerState(
            currentStation: .nts1,
            isPlaying: true,
            statusText: "Playing NTS 1",
            lastError: nil,
            updatedAt: .now
        )
        let engine = MockRadioPlaybackEngine()
        let store = InMemorySharedPlayerStateStore(initialState: persistedPlayingState)
        let reloader = MockWidgetReloader()
        let sut = RadioPlayerService(
            engine: engine,
            stateStore: store,
            widgetReloader: reloader
        )

        XCTAssertEqual(engine.playCallCount, 0)
        XCTAssertEqual(engine.pauseCallCount, 1)
        XCTAssertFalse(sut.currentState().isPlaying)
        XCTAssertEqual(sut.currentState().currentStation, .nts1)
        XCTAssertEqual(sut.currentState().statusText, "Paused")
        XCTAssertFalse(store.load().isPlaying)
        XCTAssertEqual(store.load().currentStation, .nts1)
        XCTAssertEqual(store.load().statusText, "Paused")
    }

    @MainActor
    func testFailureTransitionsToErrorIdleState() async throws {
        let engine = MockRadioPlaybackEngine()
        engine.loadError = DummyPlaybackError.streamUnavailable
        let store = InMemorySharedPlayerStateStore(initialState: .idle())
        let reloader = MockWidgetReloader()
        let sut = RadioPlayerService(
            engine: engine,
            stateStore: store,
            widgetReloader: reloader,
            initialState: .idle()
        )

        let failed = try await sut.play(station: .nts1)

        XCTAssertFalse(failed.isPlaying)
        XCTAssertEqual(failed.statusText, "Unavailable")
        XCTAssertEqual(failed.lastError, "Stream unavailable")
        // The station stays selected so the widget can say which stream failed
        // rather than falling back to a blank idle state.
        XCTAssertEqual(failed.currentStation, .nts1)
        // Connecting, then Unavailable — both are meaningful transitions.
        XCTAssertEqual(reloader.reloadCallCount, 2)
    }

    @MainActor
    func testTitlesRefreshWhileStillPlaying() async throws {
        let engine = MockRadioPlaybackEngine()
        let fetcher = SequencedMetadataFetcher([
            NTSNowPlaying(nts1Title: "Morning Show", nts2Title: "Other"),
            NTSNowPlaying(nts1Title: "Next Show", nts2Title: "Other"),
        ])
        let sut = RadioPlayerService(
            engine: engine,
            stateStore: InMemorySharedPlayerStateStore(initialState: .idle()),
            widgetReloader: MockWidgetReloader(),
            metadataService: fetcher,
            metadataRefreshInterval: .milliseconds(20),
            initialState: .idle()
        )

        _ = try await sut.play(station: .nts1)
        await simulateAndDrain(engine, .playing)

        // The show changes while the stream keeps playing; the widget must
        // follow without any new engine transition.
        try await waitUntil { sut.currentState().nts1NowTitle == "Next Show" }
        XCTAssertTrue(sut.currentState().isPlaying)

        // Pausing stops polling.
        _ = try await sut.togglePlayback()
        let callsAtPause = fetcher.callCount
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fetcher.callCount, callsAtPause)
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("condition not met within \(timeout)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// `RadioPlayerService` forwards engine callbacks through
    /// `Task { @MainActor in … }`, so a simulated engine state only lands after
    /// the current actor turn yields. Drive it and then drain the actor.
    @MainActor
    private func simulateAndDrain(
        _ engine: MockRadioPlaybackEngine,
        _ state: RadioEngineState
    ) async {
        engine.simulateEngineState(state)
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}
