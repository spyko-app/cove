import Foundation

/// Captura de tela via `/usr/sbin/screencapture` — região, janela, tela cheia ou com timer.
@MainActor
enum ScreenCapture {
    enum Mode: Equatable {
        case region
        case window
        case fullScreen
        case timer(seconds: Int)
    }

    /// Processo em andamento — guardado pra poder matar no `shutdown()` do coordinator.
    private static var running: Process?

    /// Builder puro dos argumentos do `screencapture` por modo — sem I/O, testável.
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

    /// Roda o `screencapture` e devolve todos os arquivos gerados.
    /// Em multi-display, `-x` grava `<base>` pro display 1 e `<base>-1`, `<base>-2`…
    /// (ou `<base> 2`) pros demais — por isso resolve pelo diretório, não só pela URL pedida.
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

    /// Filtra `candidates` pros arquivos que pertencem a esta captura: nome começando
    /// pelo nome-base (sem extensão) e modificados depois de `since`. Puro — sem I/O, testável.
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

    /// Chamado no shutdown do app — nunca deixa `screencapture` orfão.
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
