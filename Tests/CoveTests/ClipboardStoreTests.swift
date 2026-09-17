import XCTest
import AppKit
@testable import Cove

@MainActor final class ClipboardStoreTests: XCTestCase {
    private func tempStorage(_ prefix: String = "clip") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testIngestDedupesMovesToTopAndCaps() {
        let s = ClipboardStore(storage: tempStorage(), limit: 3)
        s.ingest(text: "a", kind: .text); s.ingest(text: "b", kind: .text); s.ingest(text: "a", kind: .text)
        XCTAssertEqual(s.entries.map(\.text), ["a", "b"])
        s.ingest(text: "c", kind: .text); s.ingest(text: "d", kind: .text)
        XCTAssertEqual(s.entries.count, 3)
        XCTAssertEqual(s.entries.first?.text, "d")
    }
    func testSearchIsCaseInsensitive() {
        let s = ClipboardStore(storage: tempStorage())
        s.ingest(text: "Reunião Cove", kind: .text); s.ingest(text: "https://x.y", kind: .url)
        XCTAssertEqual(s.search("cove").count, 1)
        XCTAssertEqual(s.search("").count, 2)
    }
    func testIgnoresEmptyAndWhitespace() {
        let s = ClipboardStore(storage: tempStorage())
        s.ingest(text: "   ", kind: .text); s.ingest(text: nil, kind: .text)
        XCTAssertTrue(s.entries.isEmpty)
    }
    func testOversizedImageIgnored() {
        let s = ClipboardStore(storage: tempStorage(), maxImageBytes: 100)
        XCTAssertFalse(s.shouldIngestImage(bytes: 200))
        XCTAssertFalse(s.shouldIngestImage(bytes: 0))
        XCTAssertTrue(s.shouldIngestImage(bytes: 50))
        XCTAssertTrue(s.shouldIngestImage(bytes: 100))
    }

    func testPinnedSurvivesLimitTrim() {
        let s = ClipboardStore(storage: tempStorage(), limit: 2)
        s.ingest(text: "a", kind: .text)
        s.togglePin(s.entries.first!.id)
        s.ingest(text: "b", kind: .text)
        s.ingest(text: "c", kind: .text)
        XCTAssertTrue(s.entries.contains { $0.text == "a" && $0.pinned })
        XCTAssertEqual(s.entries.filter { !$0.pinned }.count, 2)
        XCTAssertEqual(s.entries.count, 3)
    }

    func testPruneRemovesOnlyOldNonPinned() {
        let s = ClipboardStore(storage: tempStorage(), limit: 0, retentionDays: 7)
        let old = Date().addingTimeInterval(-10 * 86_400)
        s.ingest(text: "old", kind: .text, date: old)
        s.ingest(text: "oldPinned", kind: .text, date: old)
        s.togglePin(s.entries.first(where: { $0.text == "oldPinned" })!.id)
        s.ingest(text: "recent", kind: .text)
        s.prune()
        XCTAssertEqual(Set(s.entries.map(\.text)), Set(["oldPinned", "recent"]))
    }

    func testRetentionZeroNeverPrunes() {
        let s = ClipboardStore(storage: tempStorage(), limit: 0, retentionDays: 0)
        let old = Date().addingTimeInterval(-9999 * 86_400)
        s.ingest(text: "old", kind: .text, date: old)
        s.prune()
        XCTAssertEqual(s.entries.count, 1)
    }

    func testIngestOfPinnedTextDoesNotDuplicate() {
        let s = ClipboardStore(storage: tempStorage())
        s.ingest(text: "a", kind: .text)
        let id = s.entries.first!.id
        s.togglePin(id)
        s.ingest(text: "b", kind: .text)
        s.ingest(text: "a", kind: .text)
        XCTAssertEqual(s.entries.filter { $0.text == "a" }.count, 1)
        XCTAssertEqual(s.entries.first { $0.text == "a" }?.id, id)
        XCTAssertTrue(s.entries.first { $0.text == "a" }?.pinned == true)
    }

    func testHexColorDetection() {
        let s = ClipboardStore(storage: tempStorage())
        XCTAssertEqual(s.hexColor(in: "#fff"), "#FFF")
        XCTAssertEqual(s.hexColor(in: "#FF00AA"), "#FF00AA")
        XCTAssertEqual(s.hexColor(in: "#ff00aacc"), "#FF00AACC")
        XCTAssertEqual(s.hexColor(in: "  #abc  "), "#ABC")
        XCTAssertNil(s.hexColor(in: "abc"))
        XCTAssertNil(s.hexColor(in: "#gggggg"))
        XCTAssertNil(s.hexColor(in: "#ff"))
        XCTAssertNil(s.hexColor(in: "#fffff"))
        XCTAssertNil(s.hexColor(in: ""))
    }

    func testRenameSetsAndClearsLabel() {
        let s = ClipboardStore(storage: tempStorage())
        s.ingest(text: "a", kind: .text)
        let id = s.entries.first!.id
        s.rename(id, label: "Meu rótulo")
        XCTAssertEqual(s.entries.first?.label, "Meu rótulo")
        s.rename(id, label: "  ")
        XCTAssertNil(s.entries.first?.label)
    }

    func testImageEntryNotCreatedWhenWriteFails() async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("clip-badclips-\(UUID())")
        try? Data().write(to: tmp)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        let s = ClipboardStore(storage: tempStorage(), clipsDirectory: tmp)
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus(); NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4)); image.unlockFocus()
        let tiff = image.tiffRepresentation!
        await s.ingestImageData(tiff)
        XCTAssertTrue(s.entries.isEmpty)
    }

    func testUpdatePolicyAppliesImmediately() {
        let s = ClipboardStore(storage: tempStorage(), limit: 0, retentionDays: 0)
        let old = Date().addingTimeInterval(-10 * 86_400)
        s.ingest(text: "old", kind: .text, date: old)
        s.ingest(text: "a", kind: .text); s.ingest(text: "b", kind: .text); s.ingest(text: "c", kind: .text)
        s.updatePolicy(limit: 2, retentionDays: 7)
        XCTAssertEqual(s.entries.count, 2)
        XCTAssertFalse(s.entries.contains { $0.text == "old" })
    }

    func testIngestIfChangedSkipsWhenChangeCountAlreadySeen() {
        let s = ClipboardStore(storage: tempStorage())
        let pb = NSPasteboard(name: NSPasteboard.Name("cove-test-\(UUID())"))
        pb.clearContents(); pb.setString("externo", forType: .string)

        s.ingestIfChanged(pasteboard: pb)
        XCTAssertEqual(s.entries.map(\.text), ["externo"])

        s.ingestIfChanged(pasteboard: pb)
        XCTAssertEqual(s.entries.count, 1, "poll repetido sem novo changeCount não deve duplicar")
    }

    func testAcknowledgeOwnWriteMakesNextGeneralPollANoOp() {
        let s = ClipboardStore(storage: tempStorage())
        let pb = NSPasteboard.general
        let originalContents = pb.string(forType: .string)
        defer { pb.clearContents(); if let originalContents { pb.setString(originalContents, forType: .string) } }

        pb.clearContents(); pb.setString("escrita-propria", forType: .string)
        s.acknowledgeOwnWrite()
        s.ingestIfChanged(pasteboard: pb)
        XCTAssertTrue(s.entries.isEmpty, "acknowledgeOwnWrite deve blindar a própria escrita contra reingestão")
    }
}
