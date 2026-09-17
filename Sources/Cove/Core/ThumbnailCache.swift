import AppKit
import QuickLookThumbnailing

@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()

    @Published private(set) var images: [URL: NSImage] = [:]
    private var inFlight: Set<URL> = []

    func icon(for url: URL) -> NSImage {
        images[url] ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    func request(_ url: URL) {
        guard images[url] == nil, !inFlight.contains(url) else { return }
        inFlight.insert(url)
        Task {
            let image = await Self.generate(for: url)
            self.inFlight.remove(url)
            if let image { self.images[url] = image }
        }
    }

    private nonisolated static func generate(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64), scale: 2, representationTypes: .thumbnail)
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                continuation.resume(returning: thumbnail?.nsImage)
            }
        }
    }
}
