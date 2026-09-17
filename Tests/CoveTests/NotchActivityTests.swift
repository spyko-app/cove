import XCTest
@testable import Cove

final class NotchActivityTests: XCTestCase {
    private func testEventCountdownWindow(now: Date, start: Date) -> Bool {
        NotchActivity.eventCountdownActive(now: now, start: start)
    }

    func testActiveExactlyAtFifteenMinutesBefore() {
        let now = Date()
        XCTAssertTrue(testEventCountdownWindow(now: now, start: now.addingTimeInterval(15 * 60)))
    }

    func testInactiveMoreThanFifteenMinutesBefore() {
        let now = Date()
        XCTAssertFalse(testEventCountdownWindow(now: now, start: now.addingTimeInterval(15 * 60 + 1)))
    }

    func testActiveAtStart() {
        let now = Date()
        XCTAssertTrue(testEventCountdownWindow(now: now, start: now))
    }

    func testActiveExactlyFiveMinutesAfterStart() {
        let now = Date()
        XCTAssertTrue(testEventCountdownWindow(now: now, start: now.addingTimeInterval(-5 * 60)))
    }

    func testInactiveMoreThanFiveMinutesAfterStart() {
        let now = Date()
        XCTAssertFalse(testEventCountdownWindow(now: now, start: now.addingTimeInterval(-5 * 60 - 1)))
    }

    func testProgressStartsAtZeroAtFifteenMinutes() {
        let now = Date()
        let start = now.addingTimeInterval(15 * 60)
        XCTAssertEqual(NotchActivity.eventCountdownProgress(now: now, start: start), 0, accuracy: 0.001)
    }

    func testProgressReachesOneAtStart() {
        let now = Date()
        XCTAssertEqual(NotchActivity.eventCountdownProgress(now: now, start: now), 1, accuracy: 0.001)
    }

    func testProgressClampedAfterStart() {
        let now = Date()
        let start = now.addingTimeInterval(-60)
        XCTAssertEqual(NotchActivity.eventCountdownProgress(now: now, start: start), 1, accuracy: 0.001)
    }

    func testEventCountdownIsAmbientNotHUD() {
        XCTAssertFalse(NotchActivity.eventCountdown(title: "Standup", start: Date(), meetingURL: nil).isHUD)
    }
}
