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
// Mode, inverted (white surface / black type) in Light Mode. The active
// channel badge uses `foreground` as fill and `background` as text, so it
// inverts automatically too.
private enum NTS {
    static let background = adaptive(light: .white, dark: .black)
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
        VStack(spacing: 0) {
            Header(status: status)
                .padding(.horizontal, 14)
                .frame(height: 38)

            Rule()
            ChannelRow(station: .nts1, status: status)
            Rule()
            ChannelRow(station: .nts2, status: status)
            Rule()

            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    private var status: WidgetStatus {
        WidgetStatus(state: entry.state)
    }
}

/// Dark Mode keeps the solid black NTS surface. Light Mode uses a frosted,
/// partly see-through white so the desktop shows through softly; the white
/// wash on top keeps the black type legible over busy wallpapers.
/// (`NTS.background` itself stays opaque — it is also the active badge's text color.)
private struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            NTS.background
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.white.opacity(0.45))
        }
    }
}

private struct Rule: View {
    var body: some View {
        Rectangle()
            .fill(NTS.rule)
            .frame(height: 1)
    }
}

private struct Header: View {
    let status: WidgetStatus

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // Opens nts.live (e.g. to check what track is playing).
            Link(destination: AppConstants.ntsWebsiteURL) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("NTS RADIO")
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
private struct ChannelRow: View {
    let station: Station
    let status: WidgetStatus

    var body: some View {
        Link(destination: action.url) {
            HStack(spacing: 0) {
                // Live dot slot keeps rows aligned whether or not it is shown.
                ZStack {
                    if isActive && status.visualState == .playing {
                        LiveDot()
                    }
                }
                .frame(width: 14)

                Text(station.badgeLabel)
                    .font(NTS.font(16))
                    .foregroundStyle(isActive ? NTS.background : NTS.foreground)
                    .frame(width: 20, height: 20)
                    .background(isActive ? NTS.foreground : .clear)
                    .overlay(Rectangle().strokeBorder(NTS.foreground, lineWidth: isActive ? 0 : 1.5))

                Image(systemName: controlSymbol)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(NTS.foreground)
                    .frame(width: 30)

                Text(title)
                    .font(NTS.font(16))
                    .foregroundStyle(isActive ? NTS.foreground : NTS.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
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
        let raw = status.title(for: station) ?? "Live on \(station.badgeLabel)"
        return raw.uppercased()
    }

    private var accessibilityText: String {
        let verb = isRunning ? "Pause" : "Play"
        return "\(verb) \(station.displayName): \(status.title(for: station) ?? "")"
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
            return "LOADING \(station.badgeLabel)"
        case .playing:
            return "LIVE ON \(station.badgeLabel)"
        case .paused:
            return "PAUSED"
        case .unavailable:
            return "OFFLINE"
        }
    }
}

struct NTSWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.widgetKind, provider: NTSWidgetProvider()) { entry in
            NTSWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("NTS Live (Host)")
        .description("Play NTS 1 and NTS 2 live streams.")
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
