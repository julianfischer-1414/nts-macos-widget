import XCTest
@testable import NTSWidgetHost

final class StationTests: XCTestCase {
    func testDisplayNamesMatchExpectedStations() {
        XCTAssertEqual(Station.nts1.displayName, "NTS 1")
        XCTAssertEqual(Station.nts2.displayName, "NTS 2")
    }

    func testStreamURLsUsePublishedLiveEndpoints() {
        XCTAssertEqual(Station.nts1.streamURL.absoluteString, "https://stream-relay-geo.ntslive.net/stream")
        XCTAssertEqual(Station.nts2.streamURL.absoluteString, "https://stream-relay-geo.ntslive.net/stream2")
    }

    func testMixtapesUsePublishedMixtapeEndpoints() {
        XCTAssertEqual(Station.mixtapes.count, 16)
        XCTAssertEqual(Station.poolside.streamURL.absoluteString, "https://stream-mixtape-geo.ntslive.net/mixtape4")
        XCTAssertEqual(Station.slowFocus.streamURL.absoluteString, "https://stream-mixtape-geo.ntslive.net/mixtape")
        XCTAssertEqual(Set(Station.mixtapes.map(\.streamURL)).count, 16, "each mixtape needs its own stream")
        XCTAssertEqual(Set(Station.liveStations + Station.mixtapes), Set(Station.allCases))
        XCTAssertTrue(Station.mixtapes.allSatisfy { !$0.isLive && $0.badgeLabel == "∞" })
    }

    func testMixtapeSurvivesWidgetActionRoundTrip() {
        let action = WidgetAction.play(.slowFocus)
        XCTAssertEqual(WidgetAction(url: action.url), action)
    }
}
