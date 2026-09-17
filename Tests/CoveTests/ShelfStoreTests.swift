import XCTest
@testable import Cove

@MainActor final class ShelfStoreTests: XCTestCase {
    func testAddDedupesAndPersists() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-test-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("shelf.json")
        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        FileManager.default.createFile(atPath: a.path, contents: Data("a".utf8))
        FileManager.default.createFile(atPath: b.path, contents: Data("b".utf8))

        let s = ShelfStore(storage: file)
        s.add([a, a, b])
        XCTAssertEqual(s.items.map(\.url.lastPathComponent), ["a.txt", "b.txt"])

        let again = ShelfStore(storage: file)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(again.items.count, 2)

        s.remove(s.items[0].id)
        XCTAssertEqual(s.items.count, 1)
        s.clear()
        XCTAssertTrue(s.items.isEmpty)
    }

    func testVerificationRemovesOnlyMissingFiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-test-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("shelf.json")
        let existing = dir.appendingPathComponent("existing.txt")
        let missing = dir.appendingPathComponent("missing.txt")
        FileManager.default.createFile(atPath: existing.path, contents: Data("e".utf8))
        FileManager.default.createFile(atPath: missing.path, contents: Data("m".utf8))

        let seed = ShelfStore(storage: file)
        seed.add([existing, missing])
        try FileManager.default.removeItem(at: missing)

        let reloaded = ShelfStore(storage: file)
        XCTAssertEqual(reloaded.items.count, 2)

        await reloaded.verificationTask?.value
        XCTAssertEqual(reloaded.items.map(\.url.lastPathComponent), ["existing.txt"])
        XCTAssertFalse(reloaded.isVerifying)
    }
}
