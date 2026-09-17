@preconcurrency import AVFoundation
import CoreImage
import Foundation

/// Um frame da câmera: `work` (≤ 640 px, só pra detecção) + `native` (CIImage
/// na resolução do sensor, de onde saem os recortes — nunca reduzir pra 112).
struct CameraFrame: @unchecked Sendable {
    let id: UInt64
    let work: CGImage
    let native: CIImage
    let nativeSize: CGSize
    let at: Date
}

/// Câmera built-in do Mac (nunca Continuity Camera). Construção INOFENSIVA:
/// nenhum `AVCaptureDevice` é tocado antes de `start()`, e `start()` só é
/// chamado por gesto na página Rosto ou por scan armado com a tela bloqueada,
/// atrás de `AppEnvironment.isBundledApp && onboardingDone` (precedente do
/// crash do Bluetooth com plist via -sectcreate).
@MainActor
final class FaceCamera: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var latest: CameraFrame?
    @Published private(set) var lastError: String?
    /// `AVCaptureDevice.uniqueID` da câmera em uso — gravado no cadastro.
    @Published private(set) var cameraUniqueID: String?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.cove.notch.rosto.camera", qos: .userInitiated)
    nonisolated private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var configured = false
    private var frameCounter: UInt64 = 0

    nonisolated static let workMaxEdge: CGFloat = 640
    nonisolated static let targetFPS: Int32 = 15

    enum CameraError: LocalizedError {
        case denied, noDevice, cannotConfigure
        var errorDescription: String? {
            switch self {
            case .denied: "Sem permissão de câmera. Libere em Ajustes do Sistema › Privacidade › Câmera."
            case .noDevice: "Nenhuma câmera embutida encontrada."
            case .cannotConfigure: "A câmera não aceitou a configuração."
            }
        }
    }

    /// Efeitos de vídeo do sistema que alteram o frame (Centro de Controle).
    /// Contaminam os centróides: cadastro e scan recusam enquanto ligados.
    nonisolated static func ambientEffectsActive() -> Bool {
        if AVCaptureDevice.isPortraitEffectEnabled { return true }
        if AVCaptureDevice.isStudioLightEnabled { return true }
        if AVCaptureDevice.reactionEffectsEnabled { return true }
        if AVCaptureDevice.isBackgroundReplacementEnabled { return true }
        if AVCaptureDevice.isCenterStageEnabled { return true }
        return false
    }

    nonisolated static func builtInDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        return discovery.devices.first { !$0.isContinuityCamera } ?? AVCaptureDevice.default(for: .video)
    }

    func start() async throws {
        guard !isRunning else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var granted = status == .authorized
        if status == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .video) }
        guard granted else { throw CameraError.denied }
        if !configured { try configure() }
        let s = session
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { s.startRunning(); c.resume() }
        }
        isRunning = true
        lastError = nil
    }

    private func configure() throws {
        guard let device = Self.builtInDevice() else { throw CameraError.noDevice }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { throw CameraError.cannotConfigure }
        session.addInput(input)
        // Formato de MAIOR resolução: o recorte alinhado precisa de ≥ 160 px
        // nativos (medido: 112 px vs 448 px da mesma imagem dá d = 0,65).
        if let best = device.formats.max(by: { a, b in
            let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return Int(da.width) * Int(da.height) < Int(db.width) * Int(db.height)
        }) {
            try? device.lockForConfiguration()
            device.activeFormat = best
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Self.targetFPS)
            device.unlockForConfiguration()
        }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.cannotConfigure }
        session.addOutput(output)
        cameraUniqueID = device.uniqueID
        configured = true
    }

    func stop() async {
        guard isRunning else { return }
        let s = session
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { s.stopRunning(); c.resume() }
        }
        isRunning = false
        latest = nil
    }

    /// Pro `shutdown()` do coordinator (síncrono, sem await).
    func stopSync() {
        guard isRunning else { return }
        session.stopRunning()
        isRunning = false
        latest = nil
    }

    /// Reduz o frame nativo pro `work` (≤ `workMaxEdge` no maior lado, sem
    /// upscale). `[rev2 — verificado isolado]` Compartilhado com
    /// `FaceCalibrateCLI.frame(from:)` (T3): a paridade do offline com o app
    /// depende de os dois passarem por AQUI.
    nonisolated static func makeWorkImage(from native: CIImage, nativeSize size: CGSize, context: CIContext) -> CGImage? {
        let scale = min(1, workMaxEdge / max(size.width, size.height))
        let workCI = scale < 1 ? native.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : native
        return context.createCGImage(workCI, from: workCI.extent)
    }

    /// Recorte 1,3× do box do rosto na resolução nativa (maxEdge 448) — só
    /// pro `GlareCueExtractor` (sem máscara: a máscara cinza mataria o brilho).
    nonisolated func renderCrop(_ frame: CameraFrame, faceBoxPixels box: CGRect) -> CGImage? {
        let inset = box.insetBy(dx: -box.width * 0.15, dy: -box.height * 0.15)
        // CIImage é y-up: converte o box top-left → bottom-left
        let ci = CGRect(x: inset.minX, y: frame.nativeSize.height - inset.maxY, width: inset.width, height: inset.height)
            .intersection(CGRect(origin: .zero, size: frame.nativeSize))
        guard !ci.isEmpty else { return nil }
        var img = frame.native.cropped(to: ci)
        let maxEdge = max(ci.width, ci.height)
        if maxEdge > 448 {
            let s = 448 / maxEdge
            img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        return ciContext.createCGImage(img, from: img.extent)
    }
}

extension FaceCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let native = CIImage(cvPixelBuffer: pb)
        let size = CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
        // [rev2 — não typecheckado] mesmo helper do `rosto-calibrar` (paridade)
        guard let work = Self.makeWorkImage(from: native, nativeSize: size, context: ciContext) else { return }
        let at = Date()
        Task { @MainActor in
            self.frameCounter &+= 1
            self.latest = CameraFrame(id: self.frameCounter, work: work, native: native, nativeSize: size, at: at)
        }
    }
}
