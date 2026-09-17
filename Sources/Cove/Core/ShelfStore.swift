import AppKit
import Combine

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    let addedAt: Date
}

/// Cesta (Droppy "Basket"): arquivos arrastados pra ilha ficam aqui até serem usados.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var isVerifying = false
    /// Último erro de ação (zip etc.), mostrado pela página como aviso.
    @Published var lastError: String?
    /// Layout atual da Cesta (widgets + Quick Actions), já normalizado. Atualizado
    /// por polling do config enquanto a página está visível (`startObservingConfig`),
    /// pra refletir mudança feita nas Settings sem reabrir a ilha.
    @Published var layout: (widgets: [String], actions: [String]) = (
        ShelfLayout.normalize(NotchConfig().shelfWidgets),
        ShelfLayout.normalizeActions(NotchConfig().shelfQuickActions)
    )
    private let storage: URL
    private(set) var verificationTask: Task<Void, Never>?
    private var configCancellable: AnyCancellable?
    /// Duas telas com a Cesta aberta ao mesmo tempo: o `onDisappear` de uma
    /// não pode desligar a observação de config que a outra ainda usa (#31).
    private lazy var activeCount = ActiveCount(onFirst: { [weak self] in self?.refreshLayout() },
                                                onLast: {})
    /// Mantido forte enquanto o `NSSharingServicePicker` está aberto.
    private var sharingDelegate: SharingPickerDelegate?

    init(storage: URL = AppSupport.file("shelf.json")) {
        self.storage = storage
        guard let data = try? Data(contentsOf: storage),
              let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        // Carrega otimista: itens aparecem de cara. fileExists roda fora da
        // main thread, com timeout (#25) — volume de rede/externo desconectado
        // nunca trava o launch. No timeout, mantém os itens como carregados
        // (não some entrada real só porque estava lenta); a verificação só
        // remove os confirmados ausentes, e nunca salva por conta própria.
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

    /// Mostra o `NSSharingServicePicker` do sistema (Mail, Mensagens, iCloud
    /// Drive etc.) ancorado em `rect`/`view`. O painel da ilha fica em
    /// `.screenSaver`, então o menu do picker some atrás dele — sobe pra
    /// `.floating` enquanto ele estiver aberto e volta ao fechar (delegate
    /// é chamado com `nil` no dismiss). Delegate mantido forte no store.
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

    /// Copia os caminhos (um por linha) pro pasteboard.
    func copyPaths(_ ids: [UUID]) {
        let paths = items.filter { ids.contains($0.id) }.map(\.url.path).joined(separator: "\n")
        guard !paths.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths, forType: .string)
    }

    /// Zip via `/usr/bin/zip`, resultado adicionado à cesta. Roda fora da main
    /// thread (não bloqueia a UI); volta pro MainActor só pra `add`.
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

    /// Lê o config do disco e recomputa o layout normalizado — só usado no
    /// boot (property initializer) e como fallback se `bindConfig` nunca
    /// rodou. Com o coordinator vivo, o layout já vem de `bindConfig` (#35).
    func refreshLayout() {
        let cfg = NotchConfigStore.load()
        layout = (ShelfLayout.normalize(cfg.shelfWidgets), ShelfLayout.normalizeActions(cfg.shelfQuickActions))
    }

    /// Mantém `layout` sincronizado com `coordinator.config` — sem reler o
    /// JSON do disco a cada 2s (#35: era `startObservingConfig` com polling).
    /// Chamado UMA vez no `init` do `NotchCoordinator`; a partir daí o layout
    /// reage à mudança de config em qualquer momento, painel aberto ou não.
    func bindConfig(_ publisher: Published<NotchConfig>.Publisher) {
        configCancellable = publisher
            .map { (ShelfLayout.normalize($0.shelfWidgets), ShelfLayout.normalizeActions($0.shelfQuickActions)) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] layout in self?.layout = layout }
    }

    /// Chamar em `onAppear` da Cesta — refcount (#31): com `bindConfig` já
    /// mantendo o layout fresco, isto só garante um `refreshLayout()`
    /// imediato na 1ª abertura concorrente; nunca chamar `refreshLayout()` direto daqui.
    func startObservingConfig() { activeCount.retain() }
    /// Chamar em `onDisappear` da Cesta — contraparte de `startObservingConfig()`.
    func stopObservingConfig() { activeCount.release() }
}

/// Delegate mínimo do `NSSharingServicePicker`: só usado pra saber quando o
/// picker fecha (chamado com `serviceChoice: nil` no dismiss) e restaurar o
/// nível do painel da ilha.
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
