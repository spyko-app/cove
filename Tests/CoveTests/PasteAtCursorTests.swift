import XCTest
@testable import Cove

@MainActor
final class PasteAtCursorTests: XCTestCase {
    func testUntrustedNeverPastes() {
        XCTAssertFalse(PasteAtCursor.shouldPaste(trusted: false, frontmostBundleID: "com.other.app", selfBundleID: "com.cove.notch"))
    }

    func testFrontmostIsSelfNeverPastes() {
        XCTAssertFalse(PasteAtCursor.shouldPaste(trusted: true, frontmostBundleID: "com.cove.notch", selfBundleID: "com.cove.notch"))
    }

    func testNilFrontmostNeverPastes() {
        XCTAssertFalse(PasteAtCursor.shouldPaste(trusted: true, frontmostBundleID: nil, selfBundleID: "com.cove.notch"))
    }

    func testTrustedOtherAppPastes() {
        XCTAssertTrue(PasteAtCursor.shouldPaste(trusted: true, frontmostBundleID: "com.apple.TextEdit", selfBundleID: "com.cove.notch"))
    }
}
