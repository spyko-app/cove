import XCTest
@testable import Cove

/// #30: `UIRequest.targets` roteia hotkey/ring/jiggle/drop pra tela sob o
/// mouse, e deixa `nil` (media/ambient) mirar só a ilha PRIMÁRIA.
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
        // mesmo a primária ignora se o pedido mirou outra tela explicitamente.
        XCTAssertFalse(req.targets(displayID: screenB, primary: true))
    }

    func testDefaultDisplayIDIsNil() {
        let req = UIRequest(seq: 1, value: false)
        XCTAssertNil(req.displayID)
    }
}

/// #31: `ActiveCount` — dois "painéis" retendo/soltando não se derrubam.
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
        ac.retain()  // painel A abre: 0→1, start
        XCTAssertEqual(startCount, 1)
        ac.retain()  // painel B abre: 1→2, não reinicia
        XCTAssertEqual(startCount, 1)
        ac.release()  // painel A fecha: 2→1, B ainda usa — não pode parar
        XCTAssertEqual(stopCount, 0)
        ac.release()  // painel B fecha: 1→0, agora sim para
        XCTAssertEqual(stopCount, 1)
    }

    @MainActor
    func testExtraReleaseIsNoOp() {
        var stopCount = 0
        let ac = ActiveCount(onFirst: {}, onLast: { stopCount += 1 })
        ac.release()  // nunca reteve — não deve chamar onLast
        XCTAssertEqual(stopCount, 0)
        XCTAssertEqual(ac.count, 0)
    }
}
