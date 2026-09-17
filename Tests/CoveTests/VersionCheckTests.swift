import XCTest

@testable import Cove

final class VersionCheckTests: XCTestCase {
    func testExactMatch() {
        XCTAssertTrue(VersionCheck.matches(plist: "0.5.0", version: "0.5.0"))
    }

    func testMismatch() {
        XCTAssertFalse(VersionCheck.matches(plist: "0.4.0", version: "0.5.0"))
    }

    func testTrimsWhitespaceAndNewlines() {
        XCTAssertTrue(VersionCheck.matches(plist: "0.5.0\n", version: "  0.5.0  "))
    }

    func testEmptyVsNonEmpty() {
        XCTAssertFalse(VersionCheck.matches(plist: "", version: "0.5.0"))
    }
}
