import XCTest
@testable import Cove

final class NoteFileNameTests: XCTestCase {
    func testSanitizeStripsSlashAndColon() {
        XCTAssertEqual(NoteFileName.sanitize("Ideia/nova: parte 2"), "Ideia-nova- parte 2")
    }
    func testSanitizeEmptyFallsBackToNota() {
        XCTAssertEqual(NoteFileName.sanitize("   "), "Nota")
    }
    func testSanitizeTrimsTo80Chars() {
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(NoteFileName.sanitize(long).count, 80)
    }
    func testFirstLineSkipsHeadingMarksAndBlankLines() {
        XCTAssertEqual(NoteFileName.firstLine("\n# Título\ncorpo"), "Título")
    }
    func testFirstLineEmptyTextReturnsEmpty() {
        XCTAssertEqual(NoteFileName.firstLine(""), "")
    }
}

@MainActor final class NotesStoreTests: XCTestCase {
    private var createdRoots: [URL] = []

    override func tearDown() {
        for url in createdRoots {
            try? FileManager.default.removeItem(at: url)
        }
        createdRoots.removeAll()
        super.tearDown()
    }

    private func makeRoot() -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("notes-\(UUID())")
        createdRoots.append(url)
        return url
    }

    func testResolveRootUsesVaultWhenDirectoryExists() throws {
        let vault = makeRoot()
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let (root, isVault) = NotesStore.resolveRoot(vaultPath: vault.path)
        XCTAssertEqual(root.path, vault.path)
        XCTAssertTrue(isVault)
    }

    func testResolveRootFallsBackWhenVaultMissing() {
        let (_, isVault) = NotesStore.resolveRoot(vaultPath: "/nao/existe/\(UUID())")
        XCTAssertFalse(isVault)
    }

    func testCreateSaveLoadDeleteRoundTrip() throws {
        let root = makeRoot()
        let store = NotesStore(root: root)
        let url = store.create(title: "Minha nota")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("Minha nota"))
        store.save(url, text: "conteúdo de teste")
        XCTAssertEqual(store.load(url), "conteúdo de teste")
        XCTAssertTrue(store.notes.contains { $0.id == url })

        store.delete(url)
        XCTAssertFalse(store.notes.contains { $0.id == url })
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCreateDuplicateTitleGetsSuffix() {
        let root = makeRoot()
        let store = NotesStore(root: root)
        let first = store.create(title: "Nota")
        let second = store.create(title: "Nota")
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.lastPathComponent.contains("-2"))
    }

    func testRefreshPicksUpOneLevelOfSubfolders() throws {
        let root = makeRoot()
        let sub = root.appendingPathComponent("Daily", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let note = sub.appendingPathComponent("2026-09-09.md")
        try "oi".write(to: note, atomically: true, encoding: .utf8)

        let store = NotesStore(root: root)
        XCTAssertTrue(store.notes.contains { $0.id == note.resolvingSymlinksInPath() })
    }

    func testRefreshSkipsObsidianAndHiddenFolders() throws {
        let root = makeRoot()
        let hidden = root.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try "x".write(to: hidden.appendingPathComponent("config.md"), atomically: true, encoding: .utf8)

        let store = NotesStore(root: root)
        XCTAssertTrue(store.notes.isEmpty)
    }
}
