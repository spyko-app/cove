import XCTest
@testable import Cove

final class CardStyleTests: XCTestCase {
    func testUsesGlassWhenAllConditionsMet() {
        XCTAssertTrue(CardStyle.usesGlass(available: true, enabled: true, reduceTransparency: false))
    }

    func testNoGlassWhenUnavailable() {
        XCTAssertFalse(CardStyle.usesGlass(available: false, enabled: true, reduceTransparency: false))
    }

    func testNoGlassWhenDisabled() {
        XCTAssertFalse(CardStyle.usesGlass(available: true, enabled: false, reduceTransparency: false))
    }

    func testNoGlassWhenReduceTransparency() {
        XCTAssertFalse(CardStyle.usesGlass(available: true, enabled: true, reduceTransparency: true))
    }

    func testNoGlassWhenAllFalse() {
        XCTAssertFalse(CardStyle.usesGlass(available: false, enabled: false, reduceTransparency: true))
    }
}
