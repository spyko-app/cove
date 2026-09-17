import XCTest
@testable import Cove

final class StatsFormatTests: XCTestCase {
    func testBytesZero() {
        XCTAssertEqual(StatsFormat.bytes(0), "0 B")
    }
    func testBytesSmall() {
        XCTAssertEqual(StatsFormat.bytes(1536), "1,5 KB")
    }
    func testBytesGB() {
        XCTAssertEqual(StatsFormat.bytes(1_500_000_000), "1,4 GB")
    }
    func testPercentClampsLow() {
        XCTAssertEqual(StatsFormat.percent(-10), "0%")
    }
    func testPercentClampsHigh() {
        XCTAssertEqual(StatsFormat.percent(150), "100%")
    }
    func testPercentNormal() {
        XCTAssertEqual(StatsFormat.percent(42.4), "42%")
    }
    func testRate() {
        XCTAssertEqual(StatsFormat.rate(3_400_000), "3,2 MB/s")
    }
}
