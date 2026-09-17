import AppKit
import Foundation
import ScreenCaptureKit

/// Gravação de tela via ScreenCaptureKit — `SCStream` + `SCRecordingOutput` (macOS 15).
/// TCC de Gravação de Tela é pedido pelo sistema na primeira chamada a
/// `SCShareableContent`, nunca no boot do app — construir o serviço é inofensivo.
@MainActor
final class ScreenRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed = 0
    @Published private(set) var lastError: String?

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var url: URL?
    private var ticker: Timer?
    private var startRequested = false
    private var finishContinuation: CheckedContinuation<Void, Never>?

    /// Um arquivo de gravação só é válido se existe e tem conteúdo — puro e testável.
    static func isValidRecording(sizeBytes: Int?, exists: Bool) -> Bool {
        exists && (sizeBytes ?? 0) > 0
    }

    /// Nome do arquivo de saída — `stamp` já formatado, puro e testável.
    static func outputURL(stamp: String) -> URL {
        AppSupport.file("recordings").appendingPathComponent("Gravação \(stamp).mp4")
    }

    static func stamp(from date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: date)
    }

    /// `mm:ss` do tempo decorrido — puro e testável.
    static func formatElapsed(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func start(display: CGDirectDisplayID? = nil) async {
        guard !isRecording, !startRequested else { return }
        startRequested = true
        lastError = nil

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            startRequested = false
            showError("Sem permissão de Gravação de Tela")
            return
        }
        guard startRequested else { return }

        let targetID = display ?? Self.displayUnderMouse() ?? content.displays.first?.displayID
        guard let scDisplay = content.displays.first(where: { $0.displayID == targetID }) ?? content.displays.first else {
            startRequested = false
            showError("Nenhuma tela disponível")
            return
        }

        // nunca captura a própria ilha/painéis — exclui pelo windowID das janelas do app
        let ownWindowIDs = Set(NSApp.windows.map { CGWindowID($0.windowNumber) })
        let ownWindows = content.windows.filter { ownWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: ownWindows)

        let config = SCStreamConfiguration()
        config.width = scDisplay.width * 2
        config.height = scDisplay.height * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.capturesAudio = false
        config.showsCursor = true

        let dir = AppSupport.file("recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = Self.outputURL(stamp: Self.stamp())

        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = out
        outputConfig.outputFileType = .mp4

        let recordingOutput = SCRecordingOutput(configuration: outputConfig, delegate: self)

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try newStream.addRecordingOutput(recordingOutput)
        } catch {
            startRequested = false
            showError("Falha ao preparar a gravação")
            return
        }

        do {
            try await newStream.startCapture()
        } catch {
            startRequested = false
            showError("Falha ao iniciar a gravação")
            return
        }
        guard startRequested else {
            try? await newStream.stopCapture()
            return
        }

        stream = newStream
        output = recordingOutput
        url = out
        elapsed = 0
        isRecording = true
        startRequested = false
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
    }

    @discardableResult
    func stop() async -> URL? {
        startRequested = false
        guard isRecording, let stream, let output, let url else { return nil }
        ticker?.invalidate()
        ticker = nil
        isRecording = false
        self.stream = nil
        self.output = nil
        self.url = nil

        try? await stream.stopCapture()
        try? stream.removeRecordingOutput(output)
        await waitForFinish()

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs?[.size] as? Int
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard Self.isValidRecording(sizeBytes: size, exists: exists) else {
            try? FileManager.default.removeItem(at: url)
            showError("Gravação vazia")
            return nil
        }
        return url
    }

    private func waitForFinish() async {
        await withCheckedContinuation { continuation in
            self.finishContinuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, let pending = self.finishContinuation else { return }
                self.finishContinuation = nil
                pending.resume()
            }
        }
    }

    /// Chamado no shutdown do app (Droppy #2/#40): para a captura de forma
    /// síncrona e best-effort, sem deixar o processo sair com a sessão viva.
    func stopSync() {
        startRequested = false
        guard isRecording, let stream else { return }
        ticker?.invalidate()
        ticker = nil
        isRecording = false
        let sem = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 1)
        self.stream = nil
        output = nil
        url = nil
    }

    private func showError(_ message: String) {
        lastError = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if self?.lastError == message { self?.lastError = nil }
        }
    }

    private static func displayUnderMouse() -> CGDirectDisplayID? {
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens where NSPointInRect(mouse, screen.frame) {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                return id
            }
        }
        return NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.isRecording = false
            self.ticker?.invalidate()
            self.ticker = nil
            self.stream = nil
            self.output = nil
            self.showError("Gravação interrompida")
        }
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.finishContinuation?.resume()
            self.finishContinuation = nil
            self.showError("Falha ao gravar o vídeo")
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.finishContinuation?.resume()
            self.finishContinuation = nil
        }
    }
}
