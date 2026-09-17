import Foundation

@MainActor
final class NotificationMirror: ObservableObject {
    struct Note: Equatable, Identifiable {
        var id: Int
        var app: String
        var bundleID: String
        var title: String
        var body: String
        var date: Date
    }

    @Published private(set) var available = false
    @Published private(set) var recent: [Note] = []
    func notes(for bundleID: String) -> [Note] { recent.filter { $0.bundleID == bundleID } }
    var onNotification: ((Note) -> Void)?

    func clearHistory() { recent = [] }
    func clear(bundleID: String) { recent.removeAll { $0.bundleID == bundleID } }

    nonisolated static func group(_ notes: [Note], query: String) -> [(bundleID: String, notes: [Note])] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = q.isEmpty ? notes : notes.filter {
            $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q) || $0.app.lowercased().contains(q)
        }
        var order: [String] = []
        var buckets: [String: [Note]] = [:]
        for n in filtered {
            if buckets[n.bundleID] == nil { order.append(n.bundleID) }
            buckets[n.bundleID, default: []].append(n)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private var timer: Timer?
    private var lastRecID: Int = -1 { didSet { lastRecIDSnapshot = lastRecID } }
    nonisolated(unsafe) private var lastRecIDSnapshot: Int = -1

    nonisolated private var dbPath: String {
        NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    }

    init() {
        guard AppEnvironment.isBundledApp else { return }
        available = FileManager.default.isReadableFile(atPath: dbPath)
        guard available else { return }
        lastRecID = -1
        Task.detached(priority: .utility) { [weak self] in
            await self?.poll(limit: 20, emit: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task.detached(priority: .utility) { await self?.poll() }
        }
    }

    func recheck() {
        guard AppEnvironment.isBundledApp, !available else { return }
        let nowAvailable = FileManager.default.isReadableFile(atPath: dbPath)
        guard nowAvailable else { return }
        available = true
        lastRecID = -1
        Task.detached(priority: .utility) { [weak self] in
            await self?.poll(limit: 20, emit: false)
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task.detached(priority: .utility) { await self?.poll() }
        }
    }

    nonisolated private func pollSQL(limit: Int) -> String {
        let last = lastRecIDSnapshot
        return """
            SELECT r.rec_id, quote(r.data), a.identifier, r.delivered_date FROM record r \
            JOIN app a ON a.app_id = r.app_id \
            WHERE r.rec_id > \(last) ORDER BY r.rec_id DESC LIMIT \(limit);
            """
    }

    nonisolated private func query(_ sql: String) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = ["-readonly", "-separator", "\u{1F}", dbPath, sql]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.split(separator: "\n").map(String.init)
    }

    private func maxRecID() -> Int? {
        query("SELECT MAX(rec_id) FROM record;").first.flatMap(Int.init)
    }

    private func poll(limit: Int = 5, emit: Bool = true) async {
        let rows = await Task.detached { [sql = self.pollSQL(limit: limit)] in self.query(sql) }.value
        ingest(rows: rows, emit: emit)
    }

    func ingest(rows: [String], emit: Bool = true) {
        let before = lastRecID
        var fresh: [Note] = []
        for row in rows {
            let cols = row.split(separator: "\u{1F}", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 3, let rec = Int(cols[0]), rec > before else { continue }
            lastRecID = max(lastRecID, rec)
            let hex = cols[1].replacingOccurrences(of: "X'", with: "").replacingOccurrences(of: "'", with: "")
            guard let data = Data(hex: hex),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let req = plist["req"] as? [String: Any] else { continue }
            let title = (req["titl"] as? String) ?? ""
            let body = (req["body"] as? String) ?? ""
            guard !(title + body).isEmpty else { continue }
            let bundle = cols[2]
            let date = Date(timeIntervalSinceReferenceDate: Double(cols.count > 3 ? cols[3] : "") ?? Date().timeIntervalSinceReferenceDate)
            fresh.append(Note(id: rec, app: bundle.components(separatedBy: ".").last?.capitalized ?? "App",
                              bundleID: bundle, title: title.isEmpty ? body : title, body: title.isEmpty ? "" : body, date: date))
        }
        guard !fresh.isEmpty else { return }
        recent = Array((fresh + recent).prefix(60))
        if emit, let n = fresh.first { onNotification?(n) }
    }
}

extension Data {
    init?(hex: String) {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let b = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            bytes.append(b)
        }
        self.init(bytes)
    }
}
