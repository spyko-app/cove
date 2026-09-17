import Foundation

@MainActor
enum ScreenCapture {
    enum Mode: Equatable {
        case region
        case window
        case fullScreen
        case timer(seconds: Int)
    }

    private static var running: Process?

    static func arguments(for mode: Mode, output: URL) -> [String] {
        switch mode {
        case .region:
            return ["-i", "-x", output.path]
        case .window:
            return ["-i", "-W", "-x", output.path]
        case .fullScreen:
            return ["-x", output.path]
        case .timer(let seconds):
            let clamped = min(max(seconds, 1), 60)
            return ["-T", "\(clamped)", "-x", output.path]
        }
    }

    static func captureRegion() async -> URL? {
        await capture(.region).first
    }

    static func capture(_ mode: Mode) async -> [URL] {
        let dir = AppSupport.file("captures")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("Captura \(stamp()).png")
        let start = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = arguments(for: mode, output: out)
        running = p
        await withCheckedContinuation { c in
            p.terminationHandler = { _ in c.resume() }
            do {
                try p.run()
            } catch {
                c.resume()
            }
        }
        running = nil
        let candidates = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let mtimes = Dictionary(uniqueKeysWithValues: candidates.map { url in
            (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
        })
        return outputs(base: out, candidates: candidates, since: start, mtimes: mtimes)
    }

    static func outputs(base: URL, candidates: [URL], since: Date, mtimes: [URL: Date]) -> [URL] {
        let baseName = base.deletingPathExtension().lastPathComponent
        return candidates
            .filter { $0.deletingPathExtension().lastPathComponent.hasPrefix(baseName) }
            .filter { (mtimes[$0] ?? .distantPast) >= since }
            .sorted { lhs, rhs in
                if lhs == base { return true }
                if rhs == base { return false }
                return lhs.lastPathComponent < rhs.lastPathComponent
            }
    }

    static func cancelIfRunning() {
        running?.terminate()
        running = nil
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }
}
