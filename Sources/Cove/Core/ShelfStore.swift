import AppKit
import Combine

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    let addedAt: Date
}

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var isVerifying = false
    @Published var lastError: String?
    @Published var layout: (widgets: [String], actions: [String]) = (
        ShelfLayout.normalize(NotchConfig().shelfWidgets),
        ShelfLayout.normalizeActions(NotchConfig().shelfQuickActions)
    )
    private let storage: URL
    private(set) var verificationTask: Task<Void, Never>?
    private var configCancellable: AnyCancellable?
    private lazy var activeCount = ActiveCount(onFirst: { [weak self] in self?.refreshLayout() },
                                                onLast: {})
    private var sharingDelegate: SharingPickerDelegate?

    init(storage: URL = AppSupport.file("shelf.json")) {
        self.storage = storage
        guard let data = try? Data(contentsOf: storage),
              let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        items = saved
        isVerifying = true
        verificationTask = Task { [weak self] in
            let missing = await Self.findMissing(saved, timeout: 2)
            await MainActor.run {
                guard let self else { return }
                if !missing.isEmpty {
                    self.items.removeAll { item in missing.contains(item.id) }
                }
                self.isVerifying = false
            }
        }
    }

    private static func findMissing(_ items: [ShelfItem], timeout: TimeInterval) async -> Set<UUID> {
        await withTaskGroup(of: Set<UUID>?.self) { group in
            group.addTask {
                await Task.detached {
                    Set(items.filter { !FileManager.default.fileExists(atPath: $0.url.path) }.map(\.id))
                }.value
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let result = (await group.next() ?? nil) ?? []
            group.cancelAll()
            return result
        }
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(ShelfItem(id: UUID(), url: url, addedAt: Date()))
        }
        save()
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id }; save() }
    func clear() { items.removeAll(); save() }

    func airDrop(_ ids: [UUID]) {
        let urls = items.filter { ids.contains($0.id) }.map(\.url)
        guard !urls.isEmpty, let svc = NSSharingService(named: .sendViaAirDrop) else { return }
        svc.perform(withItems: urls)
    }

    func share(_ ids: [UUID], from view: NSView?, rect: NSRect) {
        let urls = items.filter { ids.contains($0.id) }.map(\.url)
        guard !urls.isEmpty, let view else { return }
        let picker = NSSharingServicePicker(items: urls)
        let delegate = SharingPickerDelegate { [weak self] in
            NotchPanelController.current?.popLoweredLevel()
            self?.sharingDelegate = nil
        }
        sharingDelegate = delegate
        picker.delegate = delegate
        NotchPanelController.current?.pushLoweredLevel()
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    func copyPaths(_ ids: [UUID]) {
        let paths = items.filter { ids.contains($0.id) }.map(\.url.path).joined(separator: "\n")
        guard !paths.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths, forType: .string)
    }

    func compress(_ ids: [UUID]) {
        let urls = items.filter { ids.contains($0.id) }.map(\.url)
        guard let first = urls.first else { return }
        let destDir = first.deletingLastPathComponent()
        let zipURL = Self.uniqueZipURL(in: destDir, base: urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Arquivos")
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = destDir
            process.arguments = ["-r", "-j", zipURL.path] + urls.map(\.path)
            do { try process.run() } catch {
                await MainActor.run { [weak self] in self?.lastError = "Não foi possível iniciar o zip" }
                return
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                await MainActor.run { [weak self] in self?.lastError = "Falha ao compactar (código \(process.terminationStatus))" }
                return
            }
            await MainActor.run { [weak self] in self?.add([zipURL]) }
        }
    }

    private static func uniqueZipURL(in dir: URL, base: String) -> URL {
        var candidate = dir.appendingPathComponent("\(base).zip")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n).zip")
            n += 1
        }
        return candidate
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: storage)
    }

    func refreshLayout() {
        let cfg = NotchConfigStore.load()
        layout = (ShelfLayout.normalize(cfg.shelfWidgets), ShelfLayout.normalizeActions(cfg.shelfQuickActions))
    }

    func bindConfig(_ publisher: Published<NotchConfig>.Publisher) {
        configCancellable = publisher
            .map { (ShelfLayout.normalize($0.shelfWidgets), ShelfLayout.normalizeActions($0.shelfQuickActions)) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] layout in self?.layout = layout }
    }

    func startObservingConfig() { activeCount.retain() }
    func stopObservingConfig() { activeCount.release() }
}

@MainActor
private final class SharingPickerDelegate: NSObject, NSSharingServicePickerDelegate {
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        MainActor.assumeIsolated { onDismiss() }
    }
}
