import XCTest
@testable import Cove

final class HighAlertTests: XCTestCase {
    func testExpiryInfiniteIsNil() {
        XCTAssertNil(HighAlert.expiry(from: Date(), duration: .infinite))
    }

    func testExpiry15Minutes() {
        let start = Date(timeIntervalSince1970: 0)
        let expiry = HighAlert.expiry(from: start, duration: .m15)
        XCTAssertEqual(expiry, start.addingTimeInterval(900))
    }

    func testExpiry30Minutes() {
        let start = Date(timeIntervalSince1970: 0)
        let expiry = HighAlert.expiry(from: start, duration: .m30)
        XCTAssertEqual(expiry, start.addingTimeInterval(1800))
    }

    func testExpiry60Minutes() {
        let start = Date(timeIntervalSince1970: 0)
        let expiry = HighAlert.expiry(from: start, duration: .m60)
        XCTAssertEqual(expiry, start.addingTimeInterval(3600))
    }

    func testDurationLabelsArePtBR() {
        XCTAssertEqual(HighAlert.Duration.m15.label, "15m")
        XCTAssertEqual(HighAlert.Duration.m30.label, "30m")
        XCTAssertEqual(HighAlert.Duration.m60.label, "1h")
        XCTAssertEqual(HighAlert.Duration.infinite.label, "∞")
    }
}
