import XCTest
import AppKit
@testable import Cove

final class EmojiSearchTests: XCTestCase {
    func testAccentInsensitiveMatchByName() {
        let results = EmojiSearch.matches("coracao", in: EmojiCatalog.all)
        XCTAssertTrue(results.contains { $0.char == "❤️" })
    }

    func testMatchByKeywordPtAndEn() {
        let byEn = EmojiSearch.matches("thumbs", in: EmojiCatalog.all)
        XCTAssertTrue(byEn.contains { $0.char == "👍" })
        let byPt = EmojiSearch.matches("joinha", in: EmojiCatalog.all)
        XCTAssertTrue(byPt.contains { $0.char == "👍" })
    }

    func testEmptyQueryReturnsRecentsFirst() {
        let recents = ["🔥", "🎉"]
        let results = EmojiSearch.matches("", in: EmojiCatalog.all, recents: recents)
        XCTAssertEqual(Array(results.prefix(2)).map(\.char), recents)
    }

    func testUnknownQueryReturnsEmpty() {
        let results = EmojiSearch.matches("xyzabc123nonexistent", in: EmojiCatalog.all)
        XCTAssertTrue(results.isEmpty)
    }

    func testCaseInsensitive() {
        let results = EmojiSearch.matches("FOGO", in: EmojiCatalog.all)
        XCTAssertTrue(results.contains { $0.char == "🔥" })
    }

    func testRecentsRankedFirstWhenMatchingQuery() {
        let recents = ["😀"]
        let results = EmojiSearch.matches("sorrindo", in: EmojiCatalog.all, recents: recents)
        XCTAssertEqual(results.first?.char, "😀")
    }
}

@MainActor
final class EmojiStoreTests: XCTestCase {
    func testUseCopiesAndBumpsMRU() {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent("emoji-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: storage) }
        let pb = NSPasteboard(name: NSPasteboard.Name("cove-test-\(UUID())"))
        let s = EmojiStore(storage: storage, pasteboard: pb)
        s.use("😀")
        s.use("🔥")
        s.use("😀")
        XCTAssertEqual(s.recents, ["😀", "🔥"])
        XCTAssertEqual(pb.string(forType: .string), "😀")
    }

    func testRecentsCapAtLimit() {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent("emoji-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: storage) }
        let s = EmojiStore(storage: storage, limit: 2)
        s.use("😀"); s.use("🔥"); s.use("🎉")
        XCTAssertEqual(s.recents, ["🎉", "🔥"])
    }
}
