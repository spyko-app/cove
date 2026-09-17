import AppKit
import CryptoKit
import Foundation
import LinkPresentation

@MainActor
final class LinkPreviewCache: ObservableObject {
    struct Preview: Codable, Equatable {
        var title: String?
        var host: String
        var iconPNG: Data?
    }

    @Published private(set) var previews: [String: Preview] = [:]
    private let directory: URL
    private var inFlight: Set<String> = []

    init(directory: URL = AppSupport.directory.appendingPathComponent("linkcards", isDirectory: true)) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func preview(for url: URL) -> Preview? {
        let key = Self.cacheKey(for: url)
        if let cached = previews[key] { return cached }
        if let onDisk = loadFromDisk(key: key) {
            previews[key] = onDisk
            return onDisk
        }
        return nil
    }

    func fetch(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        let key = Self.cacheKey(for: url)
        guard previews[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)

        Task {
            let result = await Self.fetchMetadata(url: url)
            await MainActor.run {
                self.inFlight.remove(key)
                self.previews[key] = result
                self.saveToDisk(key: key, preview: result)
            }
        }
    }

    private static func fetchMetadata(url: URL) async -> Preview {
        let host = url.host ?? url.absoluteString
        guard let metadata = await startFetching(url) else {
            return Preview(title: nil, host: host, iconPNG: nil)
        }
        let iconPNG = await iconPNG(from: metadata.iconProvider)
        return Preview(title: metadata.title, host: host, iconPNG: iconPNG)
    }

    @MainActor
    private static func startFetching(_ url: URL) async -> LPLinkMetadata? {
        let provider = LPMetadataProvider()
        provider.timeout = 5
        provider.shouldFetchSubresources = true
        return try? await provider.startFetchingMetadata(for: url)
    }

    private nonisolated static func iconPNG(from itemProvider: NSItemProvider?) async -> Data? {
        guard let itemProvider, itemProvider.canLoadObject(ofClass: NSImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            itemProvider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: pngData(scaling: image, to: NSSize(width: 32, height: 32)))
            }
        }
    }

    private nonisolated static func pngData(scaling image: NSImage, to size: NSSize) -> Data? {
        guard image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              )
        else { return nil }
        rep.size = size

        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let fitted = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = NSPoint(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2)

        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: origin, size: fitted), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    private func fileURL(key: String) -> URL { directory.appendingPathComponent("\(key).json") }

    private func loadFromDisk(key: String) -> Preview? {
        guard let data = try? Data(contentsOf: fileURL(key: key)) else { return nil }
        return try? JSONDecoder().decode(Preview.self, from: data)
    }

    private func saveToDisk(key: String, preview: Preview) {
        guard let data = try? JSONEncoder().encode(preview) else { return }
        try? data.write(to: fileURL(key: key))
    }
}
