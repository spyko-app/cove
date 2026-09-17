import AppKit
import QuickLookThumbnailing

struct ClipEntry: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case text, url, image, file }
    let id: UUID
    let kind: Kind
    let text: String
    let date: Date
    var pinned: Bool = false
    var label: String?
    var imagePath: String?
    var thumbnailPath: String?
    var ocrText: String?

    enum CodingKeys: String, CodingKey { case id, kind, text, date, pinned, label, imagePath, thumbnailPath, ocrText }

    init(id: UUID, kind: Kind, text: String, date: Date, pinned: Bool = false, label: String? = nil, imagePath: String? = nil, thumbnailPath: String? = nil, ocrText: String? = nil) {
        self.id = id; self.kind = kind; self.text = text; self.date = date
        self.pinned = pinned; self.label = label
        self.imagePath = imagePath; self.thumbnailPath = thumbnailPath; self.ocrText = ocrText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        label = try c.decodeIfPresent(String.self, forKey: .label)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        thumbnailPath = try c.decodeIfPresent(String.self, forKey: .thumbnailPath)
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipEntry] = []
    private let storage: URL
    private var limit: Int
    private var retentionDays: Int
    private let maxImageBytes: Int
    private var timer: Timer?
    private var pruneTimer: Timer?
    private var lastCount = NSPasteboard.general.changeCount
    nonisolated let clipsDir: URL

    init(storage: URL = AppSupport.file("clipboard.json"), limit: Int = 200, retentionDays: Int = 0, maxImageBytes: Int = 20_000_000, clipsDirectory: URL = AppSupport.directory.appendingPathComponent("clips", isDirectory: true)) {
        self.storage = storage; self.limit = limit; self.retentionDays = retentionDays; self.maxImageBytes = maxImageBytes
        clipsDir = clipsDirectory
        try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: storage), let e = try? JSONDecoder().decode([ClipEntry].self, from: d) { entries = e }
        prune()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.prune() }
        }
    }

    deinit { pruneTimer?.invalidate() }

    func shouldIngestImage(bytes: Int) -> Bool {
        bytes > 0 && bytes <= maxImageBytes
    }

    func hexColor(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let hex = trimmed.dropFirst()
        guard [3, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + hex.uppercased()
    }

    func ingest(text: String?, kind: ClipEntry.Kind, date: Date = Date()) {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        if let i = entries.firstIndex(where: { $0.text == text && $0.kind == kind && $0.pinned }) {
            var e = entries.remove(at: i)
            e = ClipEntry(id: e.id, kind: e.kind, text: e.text, date: date, pinned: e.pinned, label: e.label)
            let firstPinnedIndex = entries.firstIndex(where: \.pinned) ?? 0
            entries.insert(e, at: firstPinnedIndex)
            save()
            return
        }
        entries.removeAll { $0.text == text && $0.kind == kind && !$0.pinned }
        entries.insert(ClipEntry(id: UUID(), kind: kind, text: text, date: date), at: 0)
        trimToLimit()
        save()
    }

    private func trimToLimit() {
        guard limit > 0 else { return }
        let unpinnedCount = entries.filter { !$0.pinned }.count
        guard unpinnedCount > limit else { return }
        var toRemove = unpinnedCount - limit
        for i in entries.indices.reversed() where toRemove > 0 {
            if !entries[i].pinned {
                deleteFiles(for: entries[i])
                entries.remove(at: i); toRemove -= 1
            }
        }
    }

    private func deleteFiles(for entry: ClipEntry) {
        let fm = FileManager.default
        if let p = entry.imagePath { try? fm.removeItem(atPath: p) }
        if let p = entry.thumbnailPath { try? fm.removeItem(atPath: p) }
    }

    func togglePin(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].pinned.toggle()
        save()
    }

    func rename(_ id: UUID, label: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[i].label = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func prune(now: Date = Date()) {
        guard retentionDays > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        let before = entries.count
        entries.filter { !$0.pinned && $0.date < cutoff }.forEach(deleteFiles)
        entries.removeAll { !$0.pinned && $0.date < cutoff }
        if entries.count != before { save() }
    }

    func updatePolicy(limit: Int, retentionDays: Int) {
        self.limit = limit
        self.retentionDays = retentionDays
        trimToLimit()
        prune()
        save()
    }

    func search(_ q: String) -> [ClipEntry] {
        let q = q.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? entries : entries.filter {
            $0.text.localizedCaseInsensitiveContains(q) || ($0.ocrText?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    func copy(_ e: ClipEntry) {
        let pb = NSPasteboard.general; pb.clearContents()
        switch e.kind {
        case .file: pb.writeObjects([URL(fileURLWithPath: e.text) as NSURL])
        case .image:
            if let path = e.imagePath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                pb.setData(data, forType: .png)
            } else {
                pb.setString(e.text, forType: .string)
            }
        default: pb.setString(e.text, forType: .string)
        }
        acknowledgeOwnWrite()
    }

    func remove(_ id: UUID) {
        if let e = entries.first(where: { $0.id == id }) { deleteFiles(for: e) }
        entries.removeAll { $0.id == id }; save()
    }
    func clear() {
        entries.forEach(deleteFiles)
        entries.removeAll(); save()
    }

    func startWatching() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }
    func stopWatching() { timer?.invalidate(); timer = nil }

    func acknowledgeOwnWrite() {
        lastCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        ingestIfChanged(pasteboard: NSPasteboard.general)
    }

    func ingestIfChanged(pasteboard pb: NSPasteboard) {
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        if pb.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true { return }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let u = urls.first {
            ingest(text: u.path, kind: .file)
            return
        }
        if let s = pb.string(forType: .string) {
            ingest(text: s, kind: s.hasPrefix("http") && !s.contains(" ") ? .url : .text)
            return
        }
        guard let data = pb.data(forType: .tiff) ?? pb.data(forType: .png), shouldIngestImage(bytes: data.count) else { return }
        Task.detached { [weak self] in await self?.ingestImageData(data) }
    }

    nonisolated func ingestImageData(_ data: Data) async {
        guard let pngData = Self.pngRepresentation(from: data) else { return }
        let id = UUID()
        let fileURL = clipsDir.appendingPathComponent("\(id).png")
        do {
            try pngData.write(to: fileURL)
        } catch {
            FileHandle.standardError.write(Data("ClipboardStore: falha ao gravar imagem em \(fileURL.path): \(error)\n".utf8))
            return
        }
        guard let size = NSImage(data: pngData)?.size else { return }
        await MainActor.run { self.addImageEntry(id: id, path: fileURL, size: size) }
    }

    private func addImageEntry(id: UUID, path: URL, size: NSSize) {
        let w = Int(size.width), h = Int(size.height)
        let entry = ClipEntry(id: id, kind: .image, text: "Imagem \(w)×\(h)", date: Date(), imagePath: path.path)
        entries.insert(entry, at: 0)
        trimToLimit()
        save()
        guard entries.contains(where: { $0.id == id }) else { return }
        generateThumbnail(for: id, path: path)
        runOCR(for: id, path: path)
    }

    private func generateThumbnail(for id: UUID, path: URL) {
        Task {
            guard let data = await Self.thumbnailPNG(for: path) else { return }
            let thumbURL = self.clipsDir.appendingPathComponent("\(id)-thumb.png")
            try? data.write(to: thumbURL)
            self.setThumbnailPath(id: id, path: thumbURL.path)
        }
    }

    private func setThumbnailPath(id: UUID, path: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].thumbnailPath = path
        save()
    }

    private func runOCR(for id: UUID, path: URL) {
        Task.detached {
            guard let text = try? await OCRService().recognize(path), !text.isEmpty else { return }
            await MainActor.run { [weak self] in self?.updateOCRText(id: id, text: text) }
        }
    }

    private func updateOCRText(id: UUID, text: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].ocrText = text
        save()
    }

    private nonisolated static func pngRepresentation(from imageData: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: imageData) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private nonisolated static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private nonisolated static func thumbnailPNG(for path: URL) async -> Data? {
        let request = QLThumbnailGenerator.Request(fileAt: path, size: CGSize(width: 56, height: 40), scale: 2, representationTypes: .thumbnail)
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                guard let thumbnail else { continuation.resume(returning: nil); return }
                continuation.resume(returning: pngData(from: thumbnail.nsImage))
            }
        }
    }

    private func save() { try? JSONEncoder().encode(entries).write(to: storage) }
}
