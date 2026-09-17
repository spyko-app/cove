import AppKit
import Combine
import SwiftUI

/// Linha de widgets EMBAIXO do relógio da tela de bloqueio (estilo Alcove):
/// um `NSPanel` transparente por tela onde a ilha aparece, tingido com a cor
/// que o macOS dá ao relógio, delegado ao space SkyLight junto com a ilha.
/// Vive SÓ durante o lock: nasce em `applyLockScreenState` (depois dos 400 ms)
/// e morre no unlock — sinks cancelados, painéis desdelegados e fechados.
/// Zero timers: os itens vêm por Combine dos serviços que já existem.
@MainActor
final class LockWidgetsController {
    /// Itens compartilhados por todos os painéis (o tint é por tela).
    final class Model: ObservableObject {
        @Published var items: [LockScreenWidgetItem] = []
    }

    /// Tint de UMA tela. Nasce branco (ou com o cache) e recebe a cor do
    /// wallpaper quando o decode volta de fora da main — a row observa;
    /// nunca se reatribui `rootView` (descartaria o estado SwiftUI).
    final class TintModel: ObservableObject {
        @Published var tint: NSColor = .white
    }

    private let coordinator: NotchCoordinator
    private let model = Model()
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var tints: [CGDirectDisplayID: TintModel] = [:]
    /// Painéis já ordenados + delegados (a delegação exige `windowNumber`
    /// válido, então só acontece no 1º lote de itens não-vazio).
    private var presented: Set<CGDirectDisplayID> = []
    private var bridge: LockScreenBridge?
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: NotchCoordinator) {
        self.coordinator = coordinator
    }

    /// Cria (sem ordenar) um painel por tela e liga os sinks. `bridge` nil =
    /// preview (`COVE_PREVIEW_LOCK`): painel normal no desktop, sem space.
    func present(on screens: [NSScreen], bridge: LockScreenBridge?) {
        self.bridge = bridge
        for screen in screens {
            let id = screen.coveDisplayID
            guard panels[id] == nil else { continue }
            let tint = TintModel()
            tints[id] = tint
            panels[id] = makePanel(on: screen, tint: tint)
            loadTint(for: screen, into: tint)
        }
        guard cancellables.isEmpty else { return }
        let c = coordinator
        // `media.$nowPlaying` emite 1×/s tocando (`elapsed` entra no ==):
        // `removeDuplicates` DEPOIS do map — o painel só re-renderiza quando
        // algum texto muda de verdade.
        Publishers.CombineLatest4(c.$config.map(\.lockScreenWidgets).removeDuplicates(),
                                  c.focusActivePublisher.removeDuplicates(),
                                  c.weather.$current.removeDuplicates(),
                                  c.batteryPublisher.removeDuplicates())
            .combineLatest(c.media.$nowPlaying, c.calendar.$next, c.timers.$session.removeDuplicates())
            .map { core, media, next, timer in
                LockScreenWidgetsModel.items(config: core.0, focusActive: core.1, weather: core.2, battery: core.3,
                                             media: media, nextEvent: next, timer: timer)
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in self?.apply(items) }
            .store(in: &cancellables)
        // aparência virou no meio do lock (auto claro/escuro no pôr do sol):
        // o macOS troca o frame do wallpaper dinâmico → re-tinge. KVO no valor
        // já trocado (a notificação distribuída dispara ANTES do
        // `effectiveAppearance` atualizar). Morre no `dismiss()`, sem timer.
        if let app = NSApp {
            app.publisher(for: \.effectiveAppearance)
                .map { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reloadTints() }
                .store(in: &cancellables)
        }
    }

    /// Cancela os sinks PRIMEIRO (um sink atrasado não pode reordenar o painel
    /// depois do unlock), desdelega, fecha. Nunca vive fora do lock.
    func dismiss() {
        cancellables.removeAll()
        for (id, panel) in panels {
            if presented.contains(id) { bridge?.undelegate(panel) }
            panel.orderOut(nil)
        }
        LockScreenBridge.dlog("widgets: \(panels.count) painel(is) fechado(s)")
        panels.removeAll()
        tints.removeAll()
        presented.removeAll()
    }

    /// `hideFromCapture` ao vivo (Ajustes › esconder de capturas) — mesma
    /// regra dos painéis da ilha em `NotchPanelController.applySharing()`.
    func applySharing(hide: Bool) {
        panels.values.forEach { $0.sharingType = hide ? .none : .readOnly }
    }

    private func apply(_ items: [LockScreenWidgetItem]) {
        model.items = items
        for (id, panel) in panels {
            if items.isEmpty {
                // já ordenado: só some (re-delegar a cada mudança seria churn no space)
                if presented.contains(id) { panel.alphaValue = 0 }
                continue
            }
            if presented.contains(id) {
                if panel.alphaValue != 1 { panel.alphaValue = 1 }
                continue
            }
            panel.alphaValue = 1
            panel.orderFrontRegardless()   // windowNumber válido ANTES de delegar
            bridge?.delegate(panel)
            presented.insert(id)
            LockScreenBridge.dlog("widgets: painel \(id) apresentado com \(items.count) item(ns) — \(bridge == nil ? "preview" : "space")")
        }
    }

    private func makePanel(on screen: NSScreen, tint: TintModel) -> NSPanel {
        let frame = LockScreenLayout.widgetsFrame(screen: screen.frame)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true   // o loginwindow é dono do input
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // esconder de capturas vale pra linha de widgets também (mídia,
        // bateria, foco não podem entrar numa gravação que a ilha já evita)
        panel.sharingType = coordinator.config.hideFromCapture ? .none : .readOnly
        let hosting = NSHostingView(rootView: LockWidgetsRow(model: model, tintModel: tint))
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.setFrame(frame, display: false)
        return panel
    }

    /// Tint da tela: cache (só sucesso) → na hora; senão decodifica o
    /// wallpaper FORA da main (`Task.detached`, ImageIO é thread-safe) e
    /// publica no `TintModel` daquela tela. Aparência lida AQUI (main), não
    /// na task. `[weak self]` + lookup por id: decode que volta depois do
    /// `dismiss()` só alimenta o cache (o lock seguinte aproveita) e não
    /// toca painel morto; aparência que virou de novo no meio descarta o
    /// resultado stale.
    private func loadTint(for screen: NSScreen, into tint: TintModel) {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            tint.tint = .white   // pasta rotativa / aéreo: sem leitura
            return
        }
        let dark = LockScreenTint.isDarkAppearance
        if let c = LockScreenTint.cached(for: url, dark: dark) {
            tint.tint = c
            return
        }
        let id = screen.coveDisplayID
        Task.detached(priority: .utility) { [weak self] in
            guard let c = LockScreenTint.color(forWallpaperAt: url, dark: dark) else { return }
            await LockScreenTint.store(c, for: url, dark: dark)   // cache mesmo sem painel vivo
            await self?.applyTint(c, id: id, dark: dark)
        }
    }

    private func applyTint(_ color: NSColor, id: CGDirectDisplayID, dark: Bool) {
        guard dark == LockScreenTint.isDarkAppearance else { return }   // virou de novo: stale
        tints[id]?.tint = color
    }

    private func reloadTints() {
        for (id, tint) in tints {
            guard let screen = NSScreen.screens.first(where: { $0.coveDisplayID == id }) else { continue }
            loadTint(for: screen, into: tint)
        }
    }
}

/// HStack centrado de "ícone SF + texto" na cor do relógio, com sombra
/// APERTADA (halo de 1,5 pt funciona em 15 pt; raio 6 vira névoa): preta
/// sob tint claro, branca sob tint escuro — cobre também o fallback branco.
struct LockWidgetsRow: View {
    @ObservedObject var model: LockWidgetsController.Model
    @ObservedObject var tintModel: LockWidgetsController.TintModel

    var body: some View {
        let light = LockScreenTint.isLight(tintModel.tint)
        HStack(spacing: 28) {
            ForEach(model.items) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 14, weight: .semibold))
                    Text(item.text)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .foregroundStyle(Color(nsColor: tintModel.tint))
        .shadow(color: (light ? Color.black : Color.white).opacity(0.55), radius: 1.5, y: 0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: model.items)
    }
}
