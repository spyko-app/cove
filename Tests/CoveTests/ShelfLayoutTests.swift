import XCTest
@testable import Cove

final class ShelfLayoutTests: XCTestCase {

    func testFilesAlwaysPresentWhenMissing() {
        XCTAssertEqual(ShelfLayout.normalize(["quickActions"]), ["files", "quickActions"])
    }

    func testFilesKeptInPlaceWhenAlreadyPresent() {
        XCTAssertEqual(ShelfLayout.normalize(["quickActions", "files", "recent"]), ["quickActions", "files", "recent"])
    }

    func testDedupeWidgetsKeepsFirst() {
        XCTAssertEqual(ShelfLayout.normalize(["files", "recent", "files", "recent"]), ["files", "recent"])
    }

    func testUnknownWidgetsDropped() {
        XCTAssertEqual(ShelfLayout.normalize(["files", "xyz", "quickActions"]), ["files", "quickActions"])
    }

    func testEmptyWidgetsFallsBackToFilesOnly() {
        XCTAssertEqual(ShelfLayout.normalize([]), ["files"])
    }

    func testActionsDedupeKeepsFirst() {
        XCTAssertEqual(ShelfLayout.normalizeActions(["airdrop", "finder", "airdrop"]), ["airdrop", "finder"])
    }

    func testActionsUnknownDropped() {
        XCTAssertEqual(ShelfLayout.normalizeActions(["airdrop", "xyz", "finder"]), ["airdrop", "finder"])
    }

    func testActionsTruncatedAtLimit() {
        XCTAssertEqual(
            ShelfLayout.normalizeActions(["airdrop", "finder", "compress", "copyPath", "airdrop"], limit: 4).count,
            4)
    }

    func testActionsPaddedToMinimumTwo() {
        XCTAssertEqual(ShelfLayout.normalizeActions(["airdrop"]), ["airdrop", "finder"])
    }

    func testActionsEmptyPaddedFromDefaults() {
        XCTAssertEqual(ShelfLayout.normalizeActions([]), ["airdrop", "finder"])
    }

    func testShareActionAccepted() {
        XCTAssertEqual(ShelfLayout.normalizeActions(["share", "finder"]), ["share", "finder"])
    }
}
