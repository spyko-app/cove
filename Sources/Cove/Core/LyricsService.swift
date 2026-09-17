import CryptoKit
import Foundation

/// Cliente HTTP opcional pra letras sincronizadas via LRCLIB (lrclib.net).
/// Terceiro, desligado por padrão (`config.lyricsEnabled`). Cache local em disco
/// (30 dias pra achado, 1 dia pra "não encontrado").
@MainActor
final class LyricsService: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case found
        case notFound
        case error(String)
    }

    @Published var lines: [LyricLine] = []
    @Published var state: State = .idle

    private var currentTrackKey: String?
    private var inFlightTask: Task<Void, Never>?

    private static let cacheDir: URL = {
        let dir = AppSupport.directory.appendingPathComponent("lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let foundTTL: TimeInterval = 30 * 24 * 3600
    private static let notFoundTTL: TimeInterval = 24 * 3600

    private static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Cove/\(version) (https://github.com/cove-app/cove)"
    }

    /// Busca a letra da faixa. Só age se `lyricsEnabled` estiver ligado no config.
    /// Debounce: ignora se a faixa (título+artista) não mudou; cancela busca anterior.
    func fetch(title: String, artist: String, album: String?, duration: Double) {
        guard NotchConfigStore.load().lyricsEnabled else {
            reset()
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            reset()
            return
        }
        let key = "\(trimmedArtist)|\(trimmedTitle)|\(Int(duration))"
        guard key != currentTrackKey else { return }
        currentTrackKey = key
        inFlightTask?.cancel()
        lines = []
        state = .loading

        inFlightTask = Task { [weak self] in
            await self?.performFetch(
                title: trimmedTitle, artist: trimmedArtist, album: album, duration: duration, key: key)
        }
    }

    /// Remove todo o cache local de letras (chamado pelo botão em Settings).
    static func clearCache() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil)
        else { return }
        for item in items {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private func reset() {
        inFlightTask?.cancel()
        inFlightTask = nil
        currentTrackKey = nil
        lines = []
        state = .idle
    }

    private func performFetch(
        title: String, artist: String, album: String?, duration: Double, key: String
    ) async {
        let cacheFile = Self.cacheFile(for: key)

        if let cached = Self.readCache(cacheFile) {
            if Task.isCancelled { return }
            apply(cached, for: key)
            return
        }

        guard let url = Self.buildURL(title: title, artist: artist, album: album, duration: duration)
        else {
            if !Task.isCancelled { state = .error("URL inválida") }
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if Task.isCancelled { return }
            guard let http = response as? HTTPURLResponse else {
                state = .error("Resposta inválida")
                return
            }
            if http.statusCode == 404 {
                let entry = CachedLyrics(status: .notFound, lines: [], savedAt: Date())
                Self.writeCache(entry, to: cacheFile)
                apply(entry, for: key)
                return
            }
            guard http.statusCode == 200 else {
                state = .error("HTTP \(http.statusCode)")
                return
            }
            let decoded = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
            let parsedLines: [LyricLine]
            if let synced = decoded.syncedLyrics, !synced.isEmpty {
                parsedLines = LRCParser.parse(synced)
            } else if let plain = decoded.plainLyrics, !plain.isEmpty {
                parsedLines = [LyricLine(time: 0, text: plain)]
            } else {
                parsedLines = []
            }
            let status: CachedLyrics.Status = parsedLines.isEmpty ? .notFound : .found
            let entry = CachedLyrics(status: status, lines: parsedLines, savedAt: Date())
            Self.writeCache(entry, to: cacheFile)
            apply(entry, for: key)
        } catch {
            if Task.isCancelled { return }
            state = .error(error.localizedDescription)
        }
    }

    private func apply(_ entry: CachedLyrics, for key: String) {
        guard key == currentTrackKey else { return }
        switch entry.status {
        case .found:
            lines = entry.lines
            state = .found
        case .notFound:
            lines = []
            state = .notFound
        }
    }

    private static func buildURL(title: String, artist: String, album: String?, duration: Double) -> URL? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album, !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        comps?.queryItems = items
        return comps?.url
    }

    private static func cacheFile(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(hex).json")
    }

    private static func readCache(_ url: URL) -> CachedLyrics? {
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CachedLyrics.self, from: data)
        else { return nil }
        let ttl = entry.status == .found ? foundTTL : notFoundTTL
        guard Date().timeIntervalSince(entry.savedAt) < ttl else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return entry
    }

    private static func writeCache(_ entry: CachedLyrics, to url: URL) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url)
    }
}

private struct LRCLIBResponse: Decodable {
    let syncedLyrics: String?
    let plainLyrics: String?
}

private struct CachedLyrics: Codable {
    enum Status: String, Codable {
        case found, notFound
    }
    let status: Status
    let codableLines: [LyricLineCodable]
    let savedAt: Date

    var lines: [LyricLine] { codableLines.map { $0.line } }

    init(status: Status, lines: [LyricLine], savedAt: Date) {
        self.status = status
        self.codableLines = lines.map(LyricLineCodable.init)
        self.savedAt = savedAt
    }
}

private struct LyricLineCodable: Codable {
    let time: Double
    let text: String
    var line: LyricLine { LyricLine(time: time, text: text) }
    init(_ line: LyricLine) {
        time = line.time
        text = line.text
    }
}
