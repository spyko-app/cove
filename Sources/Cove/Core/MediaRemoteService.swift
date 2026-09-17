import AppKit
import Foundation

/// Now playing global. macOS 15.4+ bloqueia MediaRemote pra binários não
/// assinados pela Apple (provado: swift -e funciona, nosso binário recebe dict
/// vazio). Workaround provado ao vivo: adapter dylib carregada dentro do
/// /usr/bin/perl (host Apple-assinado) via DynaLoader XSUB — stream de JSON
/// por stdout, comandos por stdin. Ver adapter/mradapter.m.
struct NowPlaying: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var isPlaying = false
    var duration: Double = 0
    var elapsed: Double = 0
    var artwork: NSImage?
    var artworkTint: NSColor?

    static func == (a: NowPlaying, b: NowPlaying) -> Bool {
        a.title == b.title && a.artist == b.artist && a.isPlaying == b.isPlaying
            && a.elapsed == b.elapsed
    }
}

@MainActor
final class MediaRemoteService: ObservableObject {
    @Published var nowPlaying = NowPlaying()
    /// Quando elapsed foi atualizado pela última vez — o seeker interpola a partir daqui.
    var lastElapsedUpdate = Date()

    enum Command: Int32 {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    private var process: Process?
    private var stdinPipe: Pipe?
    private var buffer = Data()

    /// dylib + script: no bundle (Resources) ou ao lado do binário (dev).
    private static func adapterPaths() -> (script: String, dylib: String)? {
        let candidates = [
            Bundle.main.resourcePath.map { ($0 + "/adapter.pl", $0 + "/mradapter.dylib") },
            {
                let dir = (Bundle.main.executablePath! as NSString).deletingLastPathComponent
                let root = (dir as NSString).deletingLastPathComponent
                return (root + "/adapter/adapter.pl", root + "/adapter/mradapter.dylib")
            }(),
        ].compactMap { $0 }   // nunca relativo ao cwd: dylib fora do bundle assinado seria carregável
        for (s, d) in candidates
        where FileManager.default.fileExists(atPath: s) && FileManager.default.fileExists(atPath: d) {
            return (s, d)
        }
        return nil
    }

    static var available: Bool { adapterPaths() != nil }

    init() { start() }

    private func start() {
        guard let (script, dylib) = Self.adapterPaths() else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        guard (dylib as NSString).isAbsolutePath else { return }
        p.arguments = [script, dylib]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        out.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.ingest(data) }
        }
        p.terminationHandler = { [weak self] _ in
            // adapter morreu (ex.: player sumiu) — religa em 2s
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self?.start()
            }
        }
        do { try p.run() } catch { return }
        process = p
        stdinPipe = inp
    }

    private func ingest(_ data: Data) {
        // preview sem mídia (captura do HUD em largura total)
        if ProcessInfo.processInfo.environment["COVE_PREVIEW_NOMEDIA"] != nil { return }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            var np = nowPlaying
            np.title = obj["title"] as? String ?? ""
            np.artist = obj["artist"] as? String ?? ""
            np.album = obj["album"] as? String ?? ""
            np.duration = obj["duration"] as? Double ?? 0
            np.elapsed = obj["elapsed"] as? Double ?? 0
            np.isPlaying = (obj["playing"] as? Int ?? 0) == 1
            if let t = ProcessInfo.processInfo.environment["COVE_PREVIEW_TITLE"] { np.title = t }  // prova do marquee
            if let b64 = obj["artwork"] as? String, let d = Data(base64Encoded: b64) {
                np.artwork = NSImage(data: d)
                np.artworkTint = np.artwork?.dominantColor()
            }
            if np.elapsed != nowPlaying.elapsed { lastElapsedUpdate = Date() }
            nowPlaying = np
        }
    }

    func send(_ command: Command) {
        stdinPipe?.fileHandleForWriting.write(Data("cmd \(command.rawValue)\n".utf8))
    }

    func seek(to seconds: Double) {
        stdinPipe?.fileHandleForWriting.write(Data("seek \(seconds)\n".utf8))
        nowPlaying.elapsed = seconds
        lastElapsedUpdate = Date()
    }

    deinit {
        process?.terminate()
    }
}

extension NSImage {
    /// Cor média do artwork (amostragem 8x8) — tinge a waveform como no Alcove.
    func dominantColor() -> NSColor? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, n: CGFloat = 0
        let stepX = max(rep.pixelsWide / 8, 1), stepY = max(rep.pixelsHigh / 8, 1)
        for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
                guard let c = rep.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else { continue }
                r += c.redComponent; g += c.greenComponent; b += c.blueComponent; n += 1
            }
        }
        guard n > 0 else { return nil }
        let base = NSColor(red: r / n, green: g / n, blue: b / n, alpha: 1)
        return NSColor(hue: base.hueComponent,
                       saturation: min(base.saturationComponent * 1.6 + 0.15, 1),
                       brightness: max(base.brightnessComponent, 0.75), alpha: 1)
    }
}
