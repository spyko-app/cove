import XCTest
@testable import Cove

final class DropletTests: XCTestCase {
    func testMediaFirstWhenPlaying() {
        let pages = Droplet.pages(enabled: ["shelf", "apps"], hasMedia: true)
        XCTAssertEqual(pages, [.media, .shelf, .apps])
    }
    func testNoMediaSkipsMediaPage() {
        XCTAssertEqual(Droplet.pages(enabled: ["clipboard"], hasMedia: false), [.clipboard])
    }
    func testUnknownNamesIgnoredAndOrderKept() {
        XCTAssertEqual(Droplet.pages(enabled: ["tools", "xyz", "shelf"], hasMedia: false), [.tools, .shelf])
    }
    func testEmptyEnabledFallsBackToApps() {
        XCTAssertEqual(Droplet.pages(enabled: [], hasMedia: false), [.apps])
    }
    func testScrollPassthroughPages() {
        XCTAssertTrue(Droplet.shelf.scrollsInternally)
        XCTAssertTrue(Droplet.clipboard.scrollsInternally)
        XCTAssertTrue(Droplet.search.scrollsInternally)
        XCTAssertTrue(Droplet.terminal.scrollsInternally)
        XCTAssertFalse(Droplet.media.scrollsInternally)
        XCTAssertFalse(Droplet.apps.scrollsInternally)
        XCTAssertFalse(Droplet.tools.scrollsInternally)
        XCTAssertTrue(Droplet.notifications.scrollsInternally)
    }
    func testNotificationsNotInDefaultEnabled() {
        XCTAssertFalse(NotchConfig().enabledDroplets.contains("notifications"))
    }
}
