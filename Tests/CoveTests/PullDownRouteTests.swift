import XCTest
@testable import Cove

final class PullDownRouteTests: XCTestCase {
    func testOpensSearchWhenEnabledAndSearchAvailable() {
        XCTAssertEqual(PullDownRoute.target(opensSearch: true, searchEnabled: true), .search)
    }

    func testExpandsWhenOptionOff() {
        XCTAssertEqual(PullDownRoute.target(opensSearch: false, searchEnabled: true), .expand)
    }

    func testExpandsWhenSearchDropletDisabled() {
        XCTAssertEqual(PullDownRoute.target(opensSearch: true, searchEnabled: false), .expand)
    }

    func testExpandsWhenBothOff() {
        XCTAssertEqual(PullDownRoute.target(opensSearch: false, searchEnabled: false), .expand)
    }

    func testSearchDropletIsAvailableByDefault() {
        let pages = Droplet.pages(enabled: NotchConfig().enabledDroplets, hasMedia: false)
        XCTAssertTrue(pages.contains(.search))
    }
}
