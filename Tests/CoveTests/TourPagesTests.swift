import XCTest
@testable import Cove

final class TourPagesTests: XCTestCase {
    func testNextClampsAtEnd() {
        XCTAssertEqual(TourPages.next(4, count: 5), 4)
        XCTAssertEqual(TourPages.next(2, count: 5), 3)
    }

    func testPrevClampsAtStart() {
        XCTAssertEqual(TourPages.prev(0, count: 5), 0)
        XCTAssertEqual(TourPages.prev(2, count: 5), 1)
    }

    func testZeroCount() {
        XCTAssertEqual(TourPages.next(0, count: 0), 0)
        XCTAssertEqual(TourPages.prev(0, count: 0), 0)
    }
}
