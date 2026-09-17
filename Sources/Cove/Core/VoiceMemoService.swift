import AVFoundation
import Foundation
import Speech

@MainActor
final class VoiceMemoService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsed = 0
    @Published private(set) var lastError: String?

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var url: URL?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var ticker: Timer?
    private var startRequested = false
    private var writeFailures = 0

    func start() async {
        guard !isRecording, !startRequested else { return }
        startRequested = true
        lastError = nil

        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard startRequested else { return }
        guard micGranted else { startRequested = false; return }

        let auth = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard startRequested else { return }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
        let dir = AppSupport.file("memos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("Memo \(Date().formatted(.dateTime.year().month().day().hour().minute())).m4a")
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        do {
            file = try AVAudioFile(
                forWriting: out,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: fmt.sampleRate,
                    AVNumberOfChannelsKey: fmt.channelCount,
                ]
            )
        } catch {
            startRequested = false
            showError("Falha ao gravar o áudio")
            return
        }
        url = out
        transcript = ""
        elapsed = 0
        writeFailures = 0

        if auth == .authorized, let recognizer, recognizer.isAvailable {
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request = req
            task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
                guard let result else { return }
                Task { @MainActor in self?.transcript = result.bestTranscription.formattedString }
            }
        }

        let tapFile = file
        let tapRequest = request
        input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { [weak self] buf, _ in
            do {
                try tapFile?.write(from: buf)
            } catch {
                Task { @MainActor in self?.writeFailures += 1 }
            }
            tapRequest?.append(buf)
            let rms = Self.rms(buf)
            Task { @MainActor in self?.level = rms }
        }

        engine.prepare()
        guard startRequested, (try? engine.start()) != nil else {
            input.removeTap(onBus: 0)
            file = nil
            startRequested = false
            return
        }
        isRecording = true
        startRequested = false
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
    }

    @discardableResult
    func stop() async -> URL? { stopSync() }

    @discardableResult
    func stopSync() -> URL? {
        startRequested = false
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.finish()
        ticker?.invalidate()
        ticker = nil
        file = nil
        isRecording = false
        level = 0
        if writeFailures > 0 {
            showError("Falha ao gravar o áudio")
            return nil
        }
        if let url, !transcript.isEmpty {
            try? transcript.write(
                to: url.deletingPathExtension().appendingPathExtension("txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        return url
    }

    private func showError(_ message: String) {
        lastError = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if self?.lastError == message { self?.lastError = nil }
        }
    }

    nonisolated private static func rms(_ buf: AVAudioPCMBuffer) -> Float {
        guard let ch = buf.floatChannelData?[0] else { return 0 }
        let n = Int(buf.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        return min(sqrt(sum / Float(n)) * 4, 1)
    }
}
