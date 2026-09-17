import XCTest
@testable import Cove

final class RingActionTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let all: [RingAction] = [
            .droplet(.clipboard), .capture(nil), .capture(.region), .capture(.window),
            .capture(.fullScreen), .capture(.timer(seconds: 5)), .ocr, .color, .screenRecord,
            .pomodoro, .highAlert, .app(bundleID: "com.apple.Safari"), .shortcut(name: "Boa noite"),
        ]
        let data = try JSONEncoder().encode(all)
        let back = try JSONDecoder().decode([RingAction].self, from: data)
        XCTAssertEqual(back, all)
    }

    func testNormalizeDedupesAndClamps() {
        let dupes: [RingAction] = [.ocr, .ocr, .color, .color, .pomodoro]
        XCTAssertEqual(RingAction.normalize(dupes), [.ocr, .color, .pomodoro])

        let tooFew: [RingAction] = [.ocr]
        XCTAssertEqual(RingAction.normalize(tooFew), RingAction.defaults)

        let tooMany = (0..<12).map { RingAction.app(bundleID: "com.app.\($0)") }
        let clamped = RingAction.normalize(tooMany)
        XCTAssertEqual(clamped.count, 8)
        XCTAssertEqual(clamped, Array(tooMany.prefix(8)))
    }

    func testUnknownTypeDecodesToNilAndIsDropped() throws {
        let json = #"""
        [
            {"type": "ocr"},
            {"type": "futureAction", "value": "x"},
            {"type": "app", "value": "com.apple.Safari"}
        ]
        """#.data(using: .utf8)!
        let decoded = try RingAction.decodeTolerantList(json)
        XCTAssertEqual(decoded, [.ocr, .app(bundleID: "com.apple.Safari")])
    }

    func testConfigDecodeTolerantWithUnknownRingActionType() throws {
        let json = #"""
        {"ringActions": [{"type": "ocr"}, {"type": "quemSabe"}]}
        """#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(NotchConfig.self, from: json)
        XCTAssertEqual(cfg.ringActions, RingAction.normalize([.ocr]))
    }

    func testIsMissingForUnknownApp() {
        let action = RingAction.app(bundleID: "com.cove.nao-existe-de-jeito-nenhum")
        XCTAssertTrue(action.isMissing)
    }
}
