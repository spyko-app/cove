import Foundation

enum NoteFileName {
    static func sanitize(_ title: String) -> String {
        var s = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = "Nota" }
        if s.count > 80 { s = String(s.prefix(80)) }
        return s
    }

    static func firstLine(_ text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}

struct NoteFile: Identifiable, Equatable {
    let id: URL
    var title: String
    var modified: Date
}

@MainActor final class NotesStore: ObservableObject {
    @Published private(set) var notes: [NoteFile] = []
    @Published private(set) var externalChangeTick: Int = 0
    private(set) var lastError: String?
    private(set) var root: URL
    private(set) var isVault: Bool

    private var lastSavedAt: [URL: Date] = [:]

    private var watchSource: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?

    init(vaultPath: String, fileManager: FileManager = .default) {
        let resolved = Self.resolveRoot(vaultPath: vaultPath, fileManager: fileManager)
        self.root = resolved.0.resolvingSymlinksInPath()
        self.isVault = resolved.isVault
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        refresh()
        startWatching()
    }

    init(root: URL, isVault: Bool = false, fileManager: FileManager = .default) {
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root.resolvingSymlinksInPath()
        self.isVault = isVault
        refresh()
    }

    deinit {
        watchSource?.cancel()
    }

    static func resolveRoot(vaultPath: String, fileManager: FileManager = .default) -> (URL, isVault: Bool) {
        if !vaultPath.isEmpty {
            let url = URL(fileURLWithPath: vaultPath, isDirectory: true)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return (url, true)
            }
        }
        let support = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return (support.appendingPathComponent("Cove/notes", isDirectory: true), false)
    }

    func refresh() {
        let fm = FileManager.default
        var found: [NoteFile] = []
        found.append(contentsOf: scan(dir: root, fm: fm))
        if let subdirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for sub in subdirs {
                guard (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                if sub.lastPathComponent == ".obsidian" || sub.lastPathComponent.hasPrefix(".") { continue }
                found.append(contentsOf: scan(dir: sub, fm: fm))
            }
        }
        notes = found.sorted { $0.modified > $1.modified }
    }

    private func scan(dir: URL, fm: FileManager) -> [NoteFile] {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return items.compactMap { url -> NoteFile? in
            guard url.pathExtension.lowercased() == "md" else { return nil }
            if url.lastPathComponent.hasPrefix(".") { return nil }
            let resolved = url.resolvingSymlinksInPath()
            let modified = (try? resolved.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let title = resolved.deletingPathExtension().lastPathComponent
            return NoteFile(id: resolved, title: title, modified: modified)
        }
    }

    func load(_ url: URL) -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            lastError = error.localizedDescription
            return ""
        }
    }

    func save(_ url: URL, text: String) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            lastSavedAt[url] = Date()
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func diskModifiedDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func wasModifiedExternally(_ url: URL) -> Bool {
        guard let diskDate = diskModifiedDate(url) else { return false }
        guard let saved = lastSavedAt[url] else { return true }
        return diskDate > saved
    }

    @discardableResult
    func create(title: String) -> URL {
        let fm = FileManager.default
        let base = NoteFileName.sanitize(title)
        var name = "\(base).md"
        var url = root.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: url.path) {
            name = "\(base)-\(n).md"
            url = root.appendingPathComponent(name)
            n += 1
        }
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        return url.resolvingSymlinksInPath()
    }

    func delete(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startWatching() {
        let fd = open(root.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            self?.scheduleDebouncedRefresh()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watchSource = source
    }

    private func scheduleDebouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
            self?.externalChangeTick += 1
        }
    }

    func reconfigure(vaultPath: String, fileManager: FileManager = .default) {
        watchSource?.cancel()
        watchSource = nil
        debounceTask?.cancel()
        let resolved = Self.resolveRoot(vaultPath: vaultPath, fileManager: fileManager)
        try? fileManager.createDirectory(at: resolved.0, withIntermediateDirectories: true)
        root = resolved.0.resolvingSymlinksInPath()
        isVault = resolved.isVault
        lastSavedAt.removeAll()
        refresh()
        startWatching()
    }
}
