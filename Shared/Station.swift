import Foundation

/// Everything the host can play: the two live channels and NTS's Infinite
/// Mixtapes (endless themed streams).
///
/// The mixtape list and stream URLs are hard-coded from
/// `https://www.nts.live/api/v2/mixtapes` (checked 2026-11-17; the streams are
/// public, no NTS login needed). They are hard-coded on purpose: the widget
/// provider must stay side-effect-free, so it cannot fetch the list itself.
/// Raw values are persisted in the shared state file, so don't rename them.
enum Station: String, CaseIterable, Codable, Identifiable, Sendable {
    case nts1
    case nts2

    case poolside = "mixtape-poolside"
    case slowFocus = "mixtape-slow-focus"
    case lowKey = "mixtape-low-key"
    case memoryLane = "mixtape-memory-lane"
    case fourToTheFloor = "mixtape-4-to-the-floor"
    case islandTime = "mixtape-island-time"
    case theTube = "mixtape-the-tube"
    case sheetMusic = "mixtape-sheet-music"
    case feelings = "mixtape-feelings"
    case expansions = "mixtape-expansions"
    case rapHouse = "mixtape-rap-house"
    case labyrinth = "mixtape-labyrinth"
    case sweat = "mixtape-sweat"
    case otaku = "mixtape-otaku"
    case thePit = "mixtape-the-pit"
    case fieldRecordings = "mixtape-field-recordings"

    static let liveStations: [Station] = [.nts1, .nts2]

    /// In nts.live's own order.
    static let mixtapes: [Station] = [
        .poolside, .slowFocus, .lowKey, .memoryLane,
        .fourToTheFloor, .islandTime, .theTube, .sheetMusic,
        .feelings, .expansions, .rapHouse, .labyrinth,
        .sweat, .otaku, .thePit, .fieldRecordings,
    ]

    var id: String { rawValue }

    var isLive: Bool {
        self == .nts1 || self == .nts2
    }

    var displayName: String {
        switch self {
        case .nts1: return "NTS 1"
        case .nts2: return "NTS 2"
        case .poolside: return "Poolside"
        case .slowFocus: return "Slow Focus"
        case .lowKey: return "Low Key"
        case .memoryLane: return "Memory Lane"
        case .fourToTheFloor: return "4 To The Floor"
        case .islandTime: return "Island Time"
        case .theTube: return "The Tube"
        case .sheetMusic: return "Sheet Music"
        case .feelings: return "Feelings"
        case .expansions: return "Expansions"
        case .rapHouse: return "Rap House"
        case .labyrinth: return "Labyrinth"
        case .sweat: return "Sweat"
        case .otaku: return "Otaku"
        case .thePit: return "The Pit"
        case .fieldRecordings: return "Field Recordings"
        }
    }

    /// The square badge in the widget: the channel number, or ∞ for a mixtape
    /// (NTS's own mark for Infinite Mixtapes).
    var badgeLabel: String {
        switch self {
        case .nts1: return "1"
        case .nts2: return "2"
        default: return "∞"
        }
    }

    /// Short name for the widget header ("LIVE ON 1", "∞ POOLSIDE").
    var headerName: String {
        isLive ? badgeLabel : displayName.uppercased()
    }

    var streamURL: URL {
        let path: String
        switch self {
        case .nts1: return URL(string: "https://stream-relay-geo.ntslive.net/stream")!
        case .nts2: return URL(string: "https://stream-relay-geo.ntslive.net/stream2")!
        case .poolside: path = "mixtape4"
        case .slowFocus: path = "mixtape"
        case .lowKey: path = "mixtape2"
        case .memoryLane: path = "mixtape6"
        case .fourToTheFloor: path = "mixtape5"
        case .islandTime: path = "mixtape21"
        case .theTube: path = "mixtape26"
        case .sheetMusic: path = "mixtape35"
        case .feelings: path = "mixtape27"
        case .expansions: path = "mixtape3"
        case .rapHouse: path = "mixtape22"
        case .labyrinth: path = "mixtape31"
        case .sweat: path = "mixtape24"
        case .otaku: path = "mixtape36"
        case .thePit: path = "mixtape34"
        case .fieldRecordings: path = "mixtape23"
        }
        return URL(string: "https://stream-mixtape-geo.ntslive.net/\(path)")!
    }
}
