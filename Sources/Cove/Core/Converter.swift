import AVFoundation
import AppKit
import Foundation
import PDFKit

struct ConvertJob: Identifiable {
    enum State: Equatable {
        case queued
        case running
        case done(URL)
        case failed(String)
    }

    let id = UUID()
    let input: URL
    let preset: ConvertPreset
    var progress: Double = 0
    var state: State = .queued
}

@MainActor
final class Converter: ObservableObject {
    @Published private(set) var jobs: [ConvertJob] = []
    private var runningTask: Task<Void, Never>?

    func enqueue(_ urls: [URL], preset: ConvertPreset) {
        for url in urls {
            jobs.append(ConvertJob(input: url, preset: preset))
        }
        runNextIfNeeded()
    }

    func clearCompleted() {
        jobs.removeAll { if case .done = $0.state { return true }; return false }
    }

    private func runNextIfNeeded() {
        guard runningTask == nil else { return }
        guard let index = jobs.firstIndex(where: { $0.state == .queued }) else { return }
        jobs[index].state = .running
        let job = jobs[index]
        runningTask = Task { [weak self] in
            await self?.run(job)
            await MainActor.run { self?.runningTask = nil; self?.runNextIfNeeded() }
        }
    }

    private func run(_ job: ConvertJob) async {
        do {
            let output = try await convert(job)
            update(job.id) { $0.state = .done(output); $0.progress = 1 }
        } catch {
            update(job.id) { $0.state = .failed(error.localizedDescription) }
        }
    }

    private func update(_ id: UUID, _ mutate: (inout ConvertJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }

    private func convert(_ job: ConvertJob) async throws -> URL {
        switch job.preset {
        case .mp4H264, .m4aAAC, .movProRes422:
            return try await convertAVAsset(job)
        case .pdfFromImages:
            return try convertImagesToPDF(job)
        case .jpgFromPDF:
            return try convertPDFToJPG(job)
        case .pngFromImage:
            return try convertImage(job, fileType: .png)
        case .jpgFromImage:
            return try convertImage(job, fileType: .jpeg)
        }
    }

    private func convertAVAsset(_ job: ConvertJob) async throws -> URL {
        let asset = AVURLAsset(url: job.input)
        let (avPreset, outputType): (String, AVFileType) = switch job.preset {
        case .mp4H264: (AVAssetExportPresetHighestQuality, .mp4)
        case .m4aAAC: (AVAssetExportPresetAppleM4A, .m4a)
        case .movProRes422: (AVAssetExportPresetAppleProRes422LPCM, .mov)
        default: (AVAssetExportPresetHighestQuality, .mp4)
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: avPreset) else {
            throw ConverterError.exportSessionUnavailable
        }
        let output = Self.uniqueOutputURL(for: job.input, extension: job.preset.outputExtension)

        let progressTask = Task { [weak self] in
            for await state in session.states(updateInterval: 0.5) {
                if case .exporting(let progress) = state {
                    let fraction = progress.fractionCompleted
                    await MainActor.run { self?.update(job.id) { $0.progress = fraction } }
                }
            }
        }
        defer { progressTask.cancel() }
        try await session.export(to: output, as: outputType)
        return output
    }

    private func convertImagesToPDF(_ job: ConvertJob) throws -> URL {
        guard let image = NSImage(contentsOf: job.input) else { throw ConverterError.imageUnreadable }
        let document = PDFDocument()
        guard let page = PDFPage(image: image) else { throw ConverterError.pdfPageCreationFailed }
        document.insert(page, at: 0)
        let output = Self.uniqueOutputURL(for: job.input, extension: "pdf")
        guard document.write(to: output) else { throw ConverterError.writeFailed }
        return output
    }

    private func convertPDFToJPG(_ job: ConvertJob) throws -> URL {
        guard let document = PDFDocument(url: job.input) else { throw ConverterError.pdfUnreadable }
        guard document.pageCount > 0 else { throw ConverterError.pdfUnreadable }
        let base = job.input.deletingPathExtension().lastPathComponent
        let dir = job.input.deletingLastPathComponent()
        var lastOutput: URL?
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = page.thumbnail(of: size, for: .mediaBox)
            let jpegData = try Self.jpegData(from: image)
            let candidate = Self.uniqueURL(dir.appendingPathComponent("\(base)-p\(index + 1).jpg"))
            try jpegData.write(to: candidate)
            lastOutput = candidate
        }
        guard let output = lastOutput else { throw ConverterError.pdfUnreadable }
        return output
    }

    private func convertImage(_ job: ConvertJob, fileType: NSBitmapImageRep.FileType) throws -> URL {
        guard let image = NSImage(contentsOf: job.input) else { throw ConverterError.imageUnreadable }
        let data: Data
        if fileType == .jpeg {
            data = try Self.jpegData(from: image)
        } else {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let encoded = rep.representation(using: fileType, properties: [:]) else {
                throw ConverterError.imageUnreadable
            }
            data = encoded
        }
        let output = Self.uniqueOutputURL(for: job.input, extension: job.preset.outputExtension)
        try data.write(to: output)
        return output
    }

    private static func jpegData(from image: NSImage) throws -> Data {
        let size = image.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: 8,
                samplesPerPixel: 3,
                hasAlpha: false,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              )
        else { throw ConverterError.imageUnreadable }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw ConverterError.imageUnreadable }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size))
        context.flushGraphics()

        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw ConverterError.imageUnreadable
        }
        return data
    }

    private static func uniqueOutputURL(for input: URL, extension ext: String) -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        return uniqueURL(dir.appendingPathComponent("\(base).\(ext)"))
    }

    private static func uniqueURL(_ candidate: URL) -> URL {
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        let dir = candidate.deletingLastPathComponent()
        var n = 2
        var next = dir.appendingPathComponent("\(base)-\(n).\(ext)")
        while FileManager.default.fileExists(atPath: next.path) {
            n += 1
            next = dir.appendingPathComponent("\(base)-\(n).\(ext)")
        }
        return next
    }
}

enum ConverterError: LocalizedError {
    case exportSessionUnavailable
    case imageUnreadable
    case pdfUnreadable
    case pdfPageCreationFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .exportSessionUnavailable: "Não foi possível iniciar a exportação"
        case .imageUnreadable: "Não foi possível ler a imagem"
        case .pdfUnreadable: "Não foi possível ler o PDF"
        case .pdfPageCreationFailed: "Não foi possível criar a página do PDF"
        case .writeFailed: "Falha ao gravar o arquivo"
        }
    }
}
