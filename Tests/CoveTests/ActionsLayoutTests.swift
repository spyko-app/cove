import XCTest
@testable import Cove

final class ActionsLayoutTests: XCTestCase {
    func testColumnsMatchCountUpToFour() {
        XCTAssertEqual(ActionsGrid.columns(for: 1), 1)
        XCTAssertEqual(ActionsGrid.columns(for: 2), 2)
        XCTAssertEqual(ActionsGrid.columns(for: 3), 3)
        XCTAssertEqual(ActionsGrid.columns(for: 4), 4)
    }

    func testColumnsClampToFourAboveFour() {
        XCTAssertEqual(ActionsGrid.columns(for: 5), 4)
        XCTAssertEqual(ActionsGrid.columns(for: 6), 4)
        XCTAssertEqual(ActionsGrid.columns(for: 7), 4)
        XCTAssertEqual(ActionsGrid.columns(for: 8), 4)
    }
}
