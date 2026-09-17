import AppKit

enum ObsidianQuickNote {
    @discardableResult
    static func append(_ text: String, vault: URL, now: Date = Date()) throws -> URL {
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "yyyy-MM-dd"
        let hm = DateFormatter(); hm.locale = Locale(identifier: "en_US_POSIX"); hm.dateFormat = "HH:mm"
        let dir = vault.appendingPathComponent("Daily", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let note = dir.appendingPathComponent("\(day.string(from: now)).md")
        var body = (try? String(contentsOf: note, encoding: .utf8)) ?? "# \(day.string(from: now))\n"
        if !body.hasSuffix("\n") { body += "\n" }
        body += "- \(hm.string(from: now)) — \(text)\n"
        try body.write(to: note, atomically: true, encoding: .utf8)
        return note
    }

    static func open(vault: URL, note: URL) {
        let rel = note.path.replacingOccurrences(of: vault.path + "/", with: "")
        var comps = URLComponents(string: "obsidian://open")!
        comps.queryItems = [URLQueryItem(name: "vault", value: vault.lastPathComponent), URLQueryItem(name: "file", value: rel)]
        if let u = comps.url { NSWorkspace.shared.open(u) }
    }
}
