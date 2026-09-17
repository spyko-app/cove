import XCTest
@testable import Cove

final class ObsidianQuickNoteTests: XCTestCase {
    func testAppendsToDailyNote() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: vault) }
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 9; c.hour = 14; c.minute = 5
        let now = Calendar(identifier: .gregorian).date(from: c)!
        let note = try ObsidianQuickNote.append("ideia um", vault: vault, now: now)
        _ = try ObsidianQuickNote.append("ideia dois", vault: vault, now: now)
        let body = try String(contentsOf: note, encoding: .utf8)
        XCTAssertEqual(note.lastPathComponent, "2026-09-09.md")
        XCTAssertTrue(body.hasPrefix("# 2026-09-09"))
        XCTAssertTrue(body.contains("- 14:05 — ideia um"))
        XCTAssertTrue(body.contains("- 14:05 — ideia dois"))
    }
}
