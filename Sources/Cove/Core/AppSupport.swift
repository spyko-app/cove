import Foundation

/// ~/Library/Application Support/Cove — dados do usuário (cesta, clipboard, memos).
enum AppSupport {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Cove", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static func file(_ name: String) -> URL { directory.appendingPathComponent(name) }
}
