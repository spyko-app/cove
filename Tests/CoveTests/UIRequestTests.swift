import XCTest
@testable import Cove

final class UIRequestTests: XCTestCase {
    private let screenA: CGDirectDisplayID = 1
    private let screenB: CGDirectDisplayID = 2

    func testNilDisplayIDTargetsOnlyPrimary() {
        let req = UIRequest(seq: 1, value: true, displayID: nil)
        XCTAssertTrue(req.targets(displayID: screenA, primary: true))
        XCTAssertFalse(req.targets(displayID: screenA, primary: false))
    }

    func testStampedDisplayIDTargetsOnlyThatScreen() {
        let req = UIRequest(seq: 1, value: true, displayID: screenA)
        XCTAssertTrue(req.targets(displayID: screenA, primary: false))
        XCTAssertTrue(req.targets(displayID: screenA, primary: true))
        XCTAssertFalse(req.targets(displayID: screenB, primary: false))
        XCTAssertFalse(req.targets(displayID: screenB, primary: true))
    }

    func testDefaultDisplayIDIsNil() {
        let req = UIRequest(seq: 1, value: false)
        XCTAssertNil(req.displayID)
    }
}

final class ActiveCountTests: XCTestCase {
    func testNextCountRetainIncrements() {
        XCTAssertEqual(ActiveCount.nextCount(0, retain: true), 1)
        XCTAssertEqual(ActiveCount.nextCount(1, retain: true), 2)
    }

    func testNextCountReleaseNeverGoesNegative() {
        XCTAssertEqual(ActiveCount.nextCount(0, retain: false), 0)
        XCTAssertEqual(ActiveCount.nextCount(1, retain: false), 0)
        XCTAssertEqual(ActiveCount.nextCount(2, retain: false), 1)
    }

    @MainActor
    func testFirstRetainStartsLastReleaseStops() {
        var startCount = 0
        var stopCount = 0
        let ac = ActiveCount(onFirst: { startCount += 1 }, onLast: { stopCount += 1 })
        ac.retain()
        XCTAssertEqual(startCount, 1)
        ac.retain()
        XCTAssertEqual(startCount, 1)
        ac.release()
        XCTAssertEqual(stopCount, 0)
        ac.release()
        XCTAssertEqual(stopCount, 1)
    }

    @MainActor
    func testExtraReleaseIsNoOp() {
        var stopCount = 0
        let ac = ActiveCount(onFirst: {}, onLast: { stopCount += 1 })
        ac.release()
        XCTAssertEqual(stopCount, 0)
        XCTAssertEqual(ac.count, 0)
    }
}
