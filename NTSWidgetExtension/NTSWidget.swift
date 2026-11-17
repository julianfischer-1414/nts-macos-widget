import AppKit
import SwiftUI
import WidgetKit
import os

struct NTSWidgetEntry: TimelineEntry {
    let date: Date
    let state: SharedPlayerState
}

struct NTSWidgetProvider: TimelineProvider {
    private let stateStore = SharedPlayerStateFileStore()
    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "NTSWidgetProvider")

    func placeholder(in context: Context) -> NTSWidgetEntry {
        logger.log("placeholder called")
        return makeIdleEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (NTSWidgetEntry) -> Void) {
        logger.log("getSnapshot called")
        completion(makeIdleEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NTSWidgetEntry>) -> Void) {
        logger.log("getTimeline called")
        let loaded = stateStore.load()
        logger.log("getTimeline loaded isPlaying=\(loaded.isPlaying, privacy: .public) status=\(loaded.statusText, privacy: .public) station=\(loaded.currentStation?.rawValue ?? "nil", privacy: .public)")

        let now = Date.now
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now)
            ?? now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: [NTSWidgetEntry(date: now, state: loaded)], policy: .after(nextRefresh)))
    }

    private func makeIdleEntry(date: Date = .now) -> NTSWidgetEntry {
        NTSWidgetEntry(date: date, state: .idle(updatedAt: date))
    }
}

// MARK: - NTS design tokens
//
// Mirrors nts.live: pure black surface, white type, Univers-style condensed
// bold in caps, white channel squares, red live dot, 1px white rules, square
// corners. Univers Condensed is not a system font, so Helvetica Neue Condensed
// Bold (bundled with macOS) stands in; Font.custom falls back to the system
// font if it is ever missing.
//
// Colors follow the system appearance: black surface / white type in Dark
// Mode, inverted (light gray surface / black type) in Light Mode. The active
// channel badge uses `foreground` as fill and `background` as text, so it
// inverts automatically too.
private enum NTS {
    // Light Mode: a soft light gray rather than pure white, so the widget
    // sits more quietly on the desktop (a translucent surface is not possible,
    // see CLAUDE.md).
    static let background = adaptive(
        light: NSColor(calibratedWhite: 0.80, alpha: 1),
        dark: .black
    )
    static let foreground = adaptive(light: .black, dark: .white)
    static let dim = adaptive(
        light: NSColor.black.withAlphaComponent(0.55),
        dark: NSColor.white.withAlphaComponent(0.55)
    )
    static let rule = adaptive(
        light: NSColor.black.withAlphaComponent(0.9),
        dark: NSColor.white.withAlphaComponent(0.9)
    )
    static let live = Color(red: 0.93, green: 0.11, blue: 0.14)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? dark : light
        })
    }

    static func font(_ size: CGFloat) -> Font {
        .custom("HelveticaNeue-CondensedBold", size: size)
    }
}

struct NTSWidgetEntryView: View {
    let entry: NTSWidgetEntry
    var body: some View {
        content.containerBackground(for: .widget) { NTS.background }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Header(title: "NTS RADIO", status: status)
                .padding(.horizontal, 14)
                .frame(height: 34)

            Rule()
            ChannelRow(station: .nts1, status: status, height: 40)
            Rule()
            ChannelRow(station: .nts2, status: status, height: 40)
            Rule()

            // Two favourite Infinite Mixtapes share the bottom row; the large
            // Mixtapes widget has all of them.
            HStack(spacing: 0) {
                ChannelRow(station: .poolside, status: status, compact: true)
                VerticalRule()
                ChannelRow(station: .slowFocus, status: status, compact: true)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var status: WidgetStatus {
        WidgetStatus(state: entry.state)
    }
}

private struct Rule: View {
    var body: some View {
        Rectangle()
            .fill(NTS.rule)
            .frame(height: 1)
    }
}

private struct VerticalRule: View {
    var body: some View {
        Rectangle()
            .fill(NTS.rule)
            .frame(width: 1)
    }
}

private struct Header: View {
    let title: String
    let status: WidgetStatus

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // Opens nts.live (e.g. to check what track is playing).
            Link(destination: WidgetAction.openWebsite.url) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title)
                        .font(NTS.font(17))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .black))
                }
                .foregroundStyle(NTS.foreground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open nts.live")

            Spacer(minLength: 0)

            if status.visualState == .playing {
                LiveDot()
            }

            Text(status.headerText)
                .font(NTS.font(13))
                .foregroundStyle(status.visualState == .unavailable ? NTS.live : NTS.foreground)
                .lineLimit(1)
        }
    }
}

private struct LiveDot: View {
    var body: some View {
        Circle()
            .fill(NTS.live)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

/// One line of the nts.live live bar: `● [1] ▶  SHOW TITLE`.
/// Tapping the active channel toggles play/pause; tapping the other switches.
///
/// `height: nil` fills the available height. `compact` tightens spacing and
/// type for half-width cells (mixtape row, Mixtapes widget grid).
private struct ChannelRow: View {
    let station: Station
    let status: WidgetStatus
    var height: CGFloat? = nil
    var compact = false

    var body: some View {
        Link(destination: action.url) {
            HStack(spacing: 0) {
                // Live dot slot keeps rows aligned whether or not it is shown.
                ZStack {
                    if isActive && status.visualState == .playing {
                        LiveDot()
                    }
                }
                .frame(width: compact ? 12 : 14)

                Text(station.badgeLabel)
                    .font(NTS.font(compact ? 15 : 16))
                    .foregroundStyle(isActive ? NTS.background : NTS.foreground)
                    .frame(width: compact ? 18 : 20, height: compact ? 18 : 20)
                    .background(isActive ? NTS.foreground : .clear)
                    .overlay(Rectangle().strokeBorder(NTS.foreground, lineWidth: isActive ? 0 : 1.5))

                Image(systemName: controlSymbol)
                    .font(.system(size: compact ? 10 : 12, weight: .black))
                    .foregroundStyle(NTS.foreground)
                    .frame(width: compact ? 22 : 30)

                Text(title)
                    .font(NTS.font(compact ? 14 : 16))
                    .foregroundStyle(isActive ? NTS.foreground : NTS.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.trailing, compact ? 6 : 12)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height ?? .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var isActive: Bool {
        switch status.visualState {
        case .playing, .paused, .connecting:
            return status.station == station
        default:
            return false
        }
    }

    private var isRunning: Bool {
        isActive && (status.visualState == .playing || status.visualState == .connecting)
    }

    private var action: WidgetAction {
        isActive ? .toggle : .play(station)
    }

    private var controlSymbol: String {
        if isActive && status.visualState == .connecting { return "ellipsis" }
        return isRunning ? "pause.fill" : "play.fill"
    }

    private var title: String {
        let fallback = station.isLive ? "Live on \(station.badgeLabel)" : station.displayName
        return (status.title(for: station) ?? fallback).uppercased()
    }

    private var accessibilityText: String {
        let verb = isRunning ? "Pause" : "Play"
        return "\(verb) \(station.displayName)\(status.title(for: station).map { ": \($0)" } ?? "")"
    }
}

private struct WidgetStatus {
    let station: Station
    let visualState: VisualState
    private let titles: [Station: String]

    enum VisualState {
        case idle
        case connecting
        case playing
        case paused
        case unavailable
    }

    init(state: SharedPlayerState) {
        let selectedStation = state.currentStation ?? .nts1
        station = selectedStation

        var titles: [Station: String] = [:]
        for candidate in Station.allCases {
            if let title = state.nowTitle(for: candidate) {
                titles[candidate] = title
            }
        }
        self.titles = titles

        if let error = state.lastError, !error.isEmpty {
            visualState = .unavailable
            return
        }

        if state.statusText == "Unavailable" {
            visualState = .unavailable
            return
        }

        if state.isPlaying {
            if state.statusText.hasPrefix("Connecting") {
                visualState = .connecting
            } else {
                visualState = .playing
            }
            return
        }

        if state.currentStation != nil {
            visualState = .paused
            return
        }

        visualState = .idle
    }

    func title(for station: Station) -> String? {
        titles[station]
    }

    var headerText: String {
        switch visualState {
        case .idle:
            return "LIVE NOW"
        case .connecting:
            return "LOADING \(station.headerName)"
        case .playing:
            return station.isLive ? "LIVE ON \(station.headerName)" : "∞ \(station.headerName)"
        case .paused:
            return "PAUSED"
        case .unavailable:
            return "OFFLINE"
        }
    }
}

// MARK: - Mixtapes widget (systemLarge)

/// All Infinite Mixtapes in a two-column grid. Same provider and shared state
/// as the live widget, so tapping a cell plays it through the host just like
/// the live rows.
struct NTSMixtapesEntryView: View {
    let entry: NTSWidgetEntry

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "NTS MIXTAPES", status: status)
                .padding(.horizontal, 14)
                .frame(height: 38)

            Rule()

            HStack(spacing: 0) {
                column(Array(Station.mixtapes.prefix(columnLength)))
                VerticalRule()
                column(Array(Station.mixtapes.dropFirst(columnLength)))
            }
            .frame(maxHeight: .infinity)
        }
        .containerBackground(for: .widget) { NTS.background }
    }

    private var columnLength: Int {
        (Station.mixtapes.count + 1) / 2
    }

    private func column(_ stations: [Station]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(stations.enumerated()), id: \.element) { index, station in
                if index > 0 {
                    Rule()
                }
                ChannelRow(station: station, status: status, compact: true)
            }
        }
    }

    private var status: WidgetStatus {
        WidgetStatus(state: entry.state)
    }
}

struct NTSMixtapesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.mixtapesWidgetKind, provider: NTSWidgetProvider()) { entry in
            NTSMixtapesEntryView(entry: entry)
        }
        .configurationDisplayName("NTS Infinite Mixtapes")
        .description("Play any of NTS's Infinite Mixtapes.")
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
        .supportedFamilies([.systemLarge])
    }
}

struct NTSWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.widgetKind, provider: NTSWidgetProvider()) { entry in
            NTSWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("NTS Live (Host)")
        .description("Play NTS 1, NTS 2 and two Infinite Mixtapes.")
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
        .supportedFamilies([.systemMedium])
    }
}

#Preview("Idle", as: .systemMedium) {
    NTSWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: nil,
            isPlaying: false,
            statusText: "Paused",
            lastError: nil,
            updatedAt: .now
        )
    )
}

#Preview("NTS 1 Playing", as: .systemMedium) {
    NTSWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: .nts1,
            isPlaying: true,
            statusText: "Playing NTS 1",
            lastError: nil,
            updatedAt: .now,
            nts1NowTitle: "The Early Bird Show w/ Maria Somerville",
            nts2NowTitle: "NTS Guide To: Traditional Burmese Folk Music"
        )
    )
}

#Preview("NTS 2 Playing", as: .systemMedium) {
    NTSWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: .nts2,
            isPlaying: true,
            statusText: "Playing NTS 2",
            lastError: nil,
            updatedAt: .now
        )
    )
}

#Preview("Paused", as: .systemMedium) {
    NTSWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: .nts1,
            isPlaying: false,
            statusText: "Paused",
            lastError: nil,
            updatedAt: .now
        )
    )
}

#Preview("Unavailable", as: .systemMedium) {
    NTSWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: .nts1,
            isPlaying: false,
            statusText: "Unavailable",
            lastError: "Network unavailable",
            updatedAt: .now
        )
    )
}

#Preview("Mixtape Playing", as: .systemMedium) {
    NTSWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: .poolside,
            isPlaying: true,
            statusText: "Playing Poolside",
            lastError: nil,
            updatedAt: .now
        )
    )
}

#Preview("Mixtapes", as: .systemLarge) {
    NTSMixtapesWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: .islandTime,
            isPlaying: true,
            statusText: "Playing Island Time",
            lastError: nil,
            updatedAt: .now
        )
    )
}
