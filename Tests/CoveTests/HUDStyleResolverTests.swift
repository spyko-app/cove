import XCTest
@testable import Cove

final class HUDStyleResolverTests: XCTestCase {
    func testPerKindOverrideWins() {
        let styles = ["volume": "glow"]
        XCTAssertEqual(HUDStyleResolver.style(for: "volume", styles: styles, fallback: "white"), "glow")
    }

    func testInvalidValueFallsBack() {
        let styles = ["volume": "rainbow"]
        XCTAssertEqual(HUDStyleResolver.style(for: "volume", styles: styles, fallback: "accent"), "accent")
    }

    func testMissingKindFallsBack() {
        let styles = ["brightness": "glow"]
        XCTAssertEqual(HUDStyleResolver.style(for: "volume", styles: styles, fallback: "white"), "white")
    }

    func testEmptyStylesFallsBack() {
        XCTAssertEqual(HUDStyleResolver.style(for: "volume", styles: [:], fallback: "accent"), "accent")
    }
}
