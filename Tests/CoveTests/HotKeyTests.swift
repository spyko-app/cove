import Carbon
import XCTest
@testable import Cove

final class HotKeyTests: XCTestCase {
    func testParsesModifiersAndKeys() {
        let c = HotKeyCombo.parse("ctrl+opt+space")!
        XCTAssertEqual(c.keyCode, 49)
        XCTAssertEqual(c.modifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(HotKeyCombo.parse("cmd+shift+k")?.keyCode, 40)
        XCTAssertNil(HotKeyCombo.parse("banana"))
        XCTAssertNil(HotKeyCombo.parse("space"))  // sem modificador não vale
    }

    func testDuplicateComboRejected() {
        let ring = HotKeyCombo.parse("ctrl+opt+space")!
        let shelf = HotKeyCombo.parse("ctrl+opt+space")!
        let clipboard = HotKeyCombo.parse("cmd+shift+k")!
        let pairs: [(id: UInt32, combo: HotKeyCombo)] = [
            (1, ring), (100, shelf), (101, clipboard),
        ]
        let conflicts = HotKeyRegistryPlanner.conflicts(in: pairs)
        XCTAssertEqual(conflicts, [ring])
    }

    func testNoDuplicatesWhenAllDistinct() {
        let pairs: [(id: UInt32, combo: HotKeyCombo)] = [
            (1, HotKeyCombo.parse("ctrl+opt+space")!),
            (100, HotKeyCombo.parse("cmd+shift+k")!),
        ]
        XCTAssertTrue(HotKeyRegistryPlanner.conflicts(in: pairs).isEmpty)
    }

    func testDropletIDsAreStable() {
        func id(for d: Droplet) -> UInt32? {
            guard let index = Droplet.allCases.firstIndex(of: d) else { return nil }
            return 100 + UInt32(index)
        }
        var seen = Set<UInt32>()
        for d in Droplet.allCases {
            guard let a = id(for: d), let b = id(for: d) else { return XCTFail("id ausente para \(d)") }
            XCTAssertEqual(a, b)
            XCTAssertGreaterThanOrEqual(a, 100)
            XCTAssertTrue(seen.insert(a).inserted, "id duplicado para \(d)")
        }
        // Pino a ordem/rawValue dos 7 primeiros droplets: `id(for:)` deriva do
        // índice em allCases, então reordenar Droplet.swift muda ids persistidos
        // em hotkeys salvas do usuário — se isto falhar, NÃO reordene os cases,
        // só adicione novos no fim.
        XCTAssertEqual(
            Array(Droplet.allCases.map(\.rawValue).prefix(7)),
            ["media", "apps", "shelf", "clipboard", "tools", "search", "terminal"]
        )
    }
}
