import AppKit
import Combine
import SwiftUI

extension NSScreen {
    /// `CGDirectDisplayID` estável (chave de configuração por display; nunca índice — #12).
    var coveDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Painel borderless que ACEITA virar key window — sem isso, campos de texto
/// (Busca, Terminal, minutos do Timer) nunca recebem foco de digitação e o
/// Esc do Ring nunca chega (I1).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Container que aceita drop de arquivos e repassa pra cesta. `isInsideIsland`
/// hit-testa contra a ilha atual — o painel é 720×260 transparente, mas só a
/// ilha (notch ± asas colapsada, 400×170+flare expandida) aceita drop (I3).
final class DropHostView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onDragEnter: (() -> Void)?
    var isInsideIsland: ((NSPoint) -> Bool)?
    /// Só existe pro hit-test durante um arrasto de arquivo: fica POR CIMA do
    /// NSHostingView (senão o SwiftUI é achado primeiro e recusa o drop) e some
    /// pro mouse comum (cliques/hover chegam ao SwiftUI de baixo).
    var isDragActive: (() -> Bool)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? {
        (isDragActive?() ?? false) ? self : nil
    }
    private func inside(_ sender: NSDraggingInfo) -> Bool { isInsideIsland?(sender.draggingLocation) ?? true }
    private static let debug = ProcessInfo.processInfo.environment["COVE_DEBUG"] != nil
    static func dlog(_ m: String) { if debug { FileHandle.standardError.write("[drop] \(m)\n".data(using: .utf8)!) } }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.dlog("entered loc=\(sender.draggingLocation) inside=\(inside(sender))")
        guard inside(sender) else { return [] }
        onDragEnter?(); return .copy
    }
    private var lastUpdateLog = Date.distantPast
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let ok = inside(sender)
        if Date().timeIntervalSince(lastUpdateLog) > 0.1 {
            lastUpdateLog = Date()
            Self.dlog("updated loc=\(sender.draggingLocation) inside=\(ok)")
        }
        return ok ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { Self.dlog("exited") }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Self.dlog("prepare loc=\(sender.draggingLocation) inside=\(inside(sender))"); return inside(sender)
    }
    override func draggingEnded(_ sender: NSDraggingInfo) { Self.dlog("ended loc=\(sender.draggingLocation)") }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Self.dlog("perform loc=\(sender.draggingLocation) inside=\(inside(sender))")
        guard inside(sender) else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(urls); return true
    }
}

/// Painel sem borda ancorado no notch (real ou simulado), acima da barra de
/// menu, presente em todos os Spaces e por cima de apps fullscreen.
@MainActor
final class NotchPanelController {
    static var current: NotchPanelController?
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    let coordinator: NotchCoordinator

    private var scrollMonitor: Any?
    private var lastDragCount = 0
    private var swipeAccum: CGFloat = 0
    private var swipeAccumY: CGFloat = 0
    private var swipeFired = false
    private var fullscreenTimer: Timer?
    private var hiddenForFullscreen: [CGDirectDisplayID: Bool] = [:]
    /// Snapshot de `hiddenForFullscreen` no instante do lock (o lock força
    /// alpha 1 e zera o dict) — restaurado no unlock, senão a ilha aparece
    /// por cima do app em tela cheia até o próximo tick do timer (1 s).
    private var hiddenBeforeLock: [CGDirectDisplayID: Bool] = [:]
    private var lastSignature: String?
    private var reloadTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    /// Painel transparente 760×300 no topo: fora da ilha ele NÃO pode engolir
    /// cliques (dono: player do Prime Video em tela cheia ficava inacessível).
    /// `ignoresMouseEvents` fica true por padrão e vira false só com o cursor
    /// sobre a ilha, com arrasto de arquivo em curso ou com a ilha expandida.
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var dragPollTask: Task<Void, Never>?
    static let panelSize = NSSize(width: 760, height: 300)
    /// Contador de "quem pediu pra baixar o nível" (menu, QuickLook, share
    /// picker) — só volta a `.screenSaver` quando o último soltar (#18: dois
    /// pedidos concorrentes não podem se pisar restaurando cedo demais).
    private var loweredLevelCount = 0
    /// Painéis estão DENTRO do space SkyLight da tela de bloqueio agora. Enquanto
    /// true: mouse sempre ignorado, nível e alpha intocados (o WindowServer é quem
    /// manda), painéis novos nascem já delegados (`show()` no meio de um lock).
    private(set) var lockScreenActive = false
    private var unlockGraceUntil = Date.distantPast
    /// Widgets sob o relógio da tela de bloqueio — existe SÓ entre o momento
    /// da delegação (400 ms após o lock) e o unlock (`dismiss` + nil).
    private var lockWidgets: LockWidgetsController?

    init(coordinator: NotchCoordinator) {
        self.coordinator = coordinator
        // swipe horizontal sobre a ilha → faixa anterior/próxima (estilo Alcove)
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] ev in
            guard let self, let win = ev.window as? NSPanel, panels.values.contains(win) else { return ev }
            // 1 ação por gesto: dispara no limiar, trava até o dedo soltar; momentum ignorado
            // gesto novo (.began) ou fim do momentum: zera — senão swipeFired fica preso
            if ev.phase == .began || ev.momentumPhase == .ended {
                swipeAccum = 0; swipeAccumY = 0; swipeFired = false
            }
            let expanded = coordinator.isExpanded
            let scrollsInternally = expanded && (coordinator.currentDroplet?.scrollsInternally ?? false)
            if ev.momentumPhase != [] { return scrollsInternally ? ev : nil }
            if ev.phase == .ended || ev.phase == .cancelled {
                swipeAccum = 0; swipeAccumY = 0; swipeFired = false
                return scrollsInternally ? ev : nil
            }
            guard !swipeFired else { return scrollsInternally ? ev : nil }
            swipeAccum += ev.scrollingDeltaX
            swipeAccumY += ev.scrollingDeltaY
            if ProcessInfo.processInfo.environment["COVE_DEBUG"] != nil {
                FileHandle.standardError.write("[swipe] dx=\(ev.scrollingDeltaX) dy=\(ev.scrollingDeltaY) accX=\(swipeAccum) accY=\(swipeAccumY) phase=\(ev.phase.rawValue) exp=\(expanded) internal=\(scrollsInternally)\n".data(using: .utf8)!)
            }
            let vertical = abs(swipeAccumY) > abs(swipeAccum)
            if expanded {
                // ABERTA: horizontal troca de página em qualquer página (natural: dedos pra esquerda = próxima);
                // vertical troca de página só onde não há lista; nas listas o scroll é do conteúdo.
                if !vertical, abs(swipeAccum) > 50 {
                    // na página de mídia o horizontal continua sendo faixa (Alcove); nas outras, página
                    if coordinator.currentDroplet == .media {
                        if abs(swipeAccum) > 80 {
                            coordinator.media.send(swipeAccum > 0 ? .previousTrack : .nextTrack)
                            swipeFired = true
                        }
                    } else {
                        coordinator.requestPage(swipeAccum < 0 ? +1 : -1)
                        swipeFired = true
                    }
                } else if vertical, !scrollsInternally, abs(swipeAccumY) > 40, coordinator.config.verticalGestures {
                    coordinator.requestPage(swipeAccumY > 0 ? +1 : -1)
                    swipeFired = true
                } else if scrollsInternally {
                    return ev
                }
            } else {
                // FECHADA: horizontal = faixa anterior/próxima; 2 dedos pra baixo abre
                if !vertical, abs(swipeAccum) > 80 {
                    coordinator.media.send(swipeAccum > 0 ? .previousTrack : .nextTrack)
                    swipeFired = true
                } else if vertical, swipeAccumY > 40, coordinator.config.verticalGestures {
                    // puxar pra baixo = "Buscar ou perguntar" (iOS 27), com fallback
                    // pra abrir normal quando a Busca está desligada nos Ajustes
                    let hasMedia = !coordinator.media.nowPlaying.title.isEmpty
                    let searchEnabled = Droplet.pages(enabled: coordinator.config.enabledDroplets,
                                                      hasMedia: hasMedia).contains(.search)
                    switch PullDownRoute.target(opensSearch: coordinator.config.pullDownOpensSearch,
                                                searchEnabled: searchEnabled) {
                    case .search: coordinator.requestShowDroplet(.search)
                    case .expand: coordinator.requestExpand(true)
                    }
                    swipeFired = true
                }
            }
            if swipeFired, ev.phase == [] {
                // scroll sem fase (roda/evento sintético): destrava sozinho
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(350))
                    self?.swipeAccum = 0; self?.swipeAccumY = 0; self?.swipeFired = false
                }
            }
            return nil
        }
        // esconder com app em tela cheia (Alcove hideInFullscreen): checa a
        // janela frontal a cada 1s — não há notificação pública de fullscreen.
        // Só roda enquanto a opção está ligada (#34: senão é `CGWindowListCopyWindowInfo`
        // por tela, todo segundo, pra sempre, à toa).
        coordinator.$config
            .map(\.hideInFullscreen)
            .removeDuplicates()
            .sink { [weak self] on in self?.updateFullscreenTimer(enabled: on) }
            .store(in: &cancellables)
        // sleep/wake/lid-close/reconexão: caminho ÚNICO pra reload(), debounced
        // 500ms — nunca reage a todo evento, só quando a config relevante muda (#1, #14).
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload() }
        }
        wsnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload() }
        }
        // passthrough do mouse reage a ilha aberta/grade/arrasto. UMA assinatura
        // pela vida do controller (antes vivia em `show()` e acumulava +1 sink
        // por `reload()`); com `panels` vazio `updateMousePassthrough` é no-op.
        // `DispatchQueue.main` (não `RunLoop.main`, que só entrega em modo
        // .default) — precedente `ShelfStore.bindConfig`.
        coordinator.$isExpanded.merge(with: coordinator.$showActions, coordinator.$dragActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMousePassthrough() }
            .store(in: &cancellables)
        // tela de bloqueio: delega os painéis ao space SkyLight SÓ enquanto
        // bloqueada e com o toggle ligado; desdelega no unlock (ou toggle off).
        // `.shared` é lazy — tocar aqui carrega a bridge e loga se degradou.
        // `DispatchQueue.main` pra entregar mesmo com o runloop em .modalPanel/
        // .eventTracking (NSOpenPanel.runModal, menu.popUp) — `RunLoop.main`
        // deixaria a ilha fora do lock até o painel/menu fechar.
        LockScreenBridge.dlog("bridge \(LockScreenBridge.isAvailable ? "disponível" : "INDISPONÍVEL (SkyLight não carregou)")")
        coordinator.$isScreenLocked.removeDuplicates()
            // snapshot SÍNCRONO de "ilha estava aberta": `@Published` emite no
            // willSet, antes de a NotchView recolher — aqui `isExpanded` ainda é
            // o valor pré-lock. Decide se a delegação espera o spring de fechar.
            .map { [weak coordinator] locked in
                (locked: locked, wasExpanded: locked && (coordinator?.isExpanded ?? false))
            }
            .combineLatest(coordinator.$config.map(\.showOnLockScreen).removeDuplicates())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lock, enabled in
                self?.applyLockScreenState(locked: lock.locked, enabled: enabled, wasExpanded: lock.wasExpanded)
            }
            .store(in: &cancellables)
    }

    /// Nível que os painéis DEVEM ter fora do lock, derivado da contabilidade
    /// (`loweredLevelCount` > `draggingLevel` > `.screenSaver`).
    private var desiredLevel: NSWindow.Level {
        if loweredLevelCount > 0 { return .floating }
        return draggingLevel ? Self.dragLevel : .screenSaver
    }

    /// Ponto ÚNICO que escreve `panel.level` — no-op enquanto delegado ao lock
    /// (mexer no nível lá dentro devolveria a janela a um space normal).
    private func applyLevel() {
        guard !lockScreenActive else { return }
        let lvl = desiredLevel
        panels.values.forEach { if $0.level != lvl { $0.level = lvl } }
    }

    /// Entra/sai do modo tela-de-bloqueio conforme a regra pura `LockScreenPolicy`.
    /// `wasExpanded` = ilha aberta no instante do lock (snapshot do sink).
    private func applyLockScreenState(locked: Bool, enabled: Bool, wasExpanded: Bool) {
        // preview (`COVE_PREVIEW_LOCK=1`): nada vai pro space — a ilha mostra o
        // cadeado (estado da view) e o painel de widgets nasce no desktop. Só
        // `locked` importa: o toggle desligado no config do dono deixaria a
        // captura vazia. ANTES do guard (want == lockScreenActive == false).
        if NotchCoordinator.previewLock {
            if locked { syncLockWidgets(bridge: nil) } else { dismissLockWidgets() }
            return
        }
        let want = LockScreenPolicy.shouldDelegate(locked: locked, enabled: enabled,
                                                   bridgeAvailable: LockScreenBridge.isAvailable)
        guard want != lockScreenActive, let bridge = LockScreenBridge.shared else { return }
        lockScreenActive = want
        LockScreenBridge.dlog("\(want ? "delegando" : "desdelegando") \(panels.count) painel(is) — locked=\(locked) enabled=\(enabled) wasExpanded=\(wasExpanded)")
        if want {
            // alpha 1 (podia estar escondida por app em tela cheia) e mouse
            // ignorado: o loginwindow é dono do input, não existe hover no lock.
            hiddenBeforeLock = hiddenForFullscreen
            hiddenForFullscreen.removeAll()
            for panel in panels.values {
                panel.alphaValue = 1
                panel.ignoresMouseEvents = true
            }
            // ilha aberta (Clipboard/Notificações/Busca/Notas): espera o spring
            // de recolhimento (0,34 s) ANTES de entrar no space 400 — senão o
            // conteúdo expandido fica ~300 ms composto por cima do loginwindow.
            // Painel não delegado é invisível no lock, então sem mexer em alpha.
            // Task one-shot guardada por `lockScreenActive` (destravou no meio:
            // nada a fazer); `show()` durante a espera já delega o painel novo
            // e delegar de novo o mesmo space é idempotente.
            // Espera SEMPRE (re-revisão 12/set): `isExpanded` é um Bool único
            // escrito por cada NotchView — com 2 telas, ou com o recolhimento
            // já em curso (hover-out), o snapshot lê false com conteúdo ainda
            // na tela. 0,4 s depois do fade do macOS ninguém percebe.
            _ = wasExpanded
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, lockScreenActive else { return }
                panels.values.forEach { bridge.delegate($0) }
                // widgets sob o relógio: mesmo instante, mesmo space
                syncLockWidgets(bridge: bridge)
            }
        } else {
            dismissLockWidgets()
            for panel in panels.values {
                bridge.undelegate(panel)
                // depois de sair do space SkyLight, reordena pra o WindowServer
                // reatribuir pelo collectionBehavior (canJoinAllSpaces) — mesmo
                // windowNumber, provado na sonda; belt-and-braces barato.
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
            // restaura o que estava escondido por app em tela cheia ANTES do
            // lock — alpha E dict juntos: só o dict deixaria a ilha visível pra
            // sempre (o guard do `checkFullscreen` veria true == true).
            if coordinator.config.hideInFullscreen {
                for (id, hidden) in hiddenBeforeLock where hidden {
                    guard let panel = panels[id] else { continue }
                    panel.alphaValue = 0
                    hiddenForFullscreen[id] = true
                }
            }
            hiddenBeforeLock.removeAll()
            unlockGraceUntil = Date().addingTimeInterval(0.6)   // tick do timer de 1 s não desfaz a restauração
            applyLevel()
            updateMousePassthrough()
            // reconcilia (app saiu da tela cheia durante o lock) um pouco
            // depois: no instante do unlock o frontmost ainda pode ser o
            // loginwindow e um `checkFullscreen()` cru desfaria a restauração.
            // O timer de 1 s segue como rede.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !lockScreenActive else { return }
                checkFullscreen()
            }
        }
    }

    /// Garante o painel de widgets nas telas que TÊM ilha agora (idempotente:
    /// `reload()` no meio do lock recria os painéis e chama de novo). `bridge`
    /// nil = preview no desktop, sem space.
    private func syncLockWidgets(bridge: LockScreenBridge?) {
        let screens = NSScreen.screens.filter { panels[$0.coveDisplayID] != nil }
        guard !screens.isEmpty else { return }
        if lockWidgets == nil { lockWidgets = LockWidgetsController(coordinator: coordinator) }
        lockWidgets?.present(on: screens, bridge: bridge)
    }

    private func dismissLockWidgets() {
        lockWidgets?.dismiss()
        lockWidgets = nil
    }

    /// Frontmost app com janela cobrindo exatamente `screen` (layer 0) = fullscreen naquela tela.
    /// Estado de HUD é por display — nunca decide global (#11).
    private func frontmostIsFullscreen(on screen: NSScreen) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let width = b["Width"] ?? 0, height = b["Height"] ?? 0
            if abs(width - screen.frame.width) < 2 && abs(height - screen.frame.height) < 2 {
                return true
            }
        }
        return false
    }

    /// Liga/desliga o polling de 1s conforme `hideInFullscreen` (#34). Desligar
    /// também restaura qualquer painel que tenha ficado invisível por causa dele.
    private func updateFullscreenTimer(enabled: Bool) {
        guard enabled else {
            fullscreenTimer?.invalidate()
            fullscreenTimer = nil
            hiddenBeforeLock.removeAll()   // toggle desligado no meio do lock: não re-esconde no unlock
            guard !hiddenForFullscreen.isEmpty else { return }
            hiddenForFullscreen.removeAll()
            panels.values.forEach { $0.alphaValue = 1 }
            return
        }
        guard fullscreenTimer == nil else { return }
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkFullscreen() }
        }
    }

    /// Avalia por tela — HUD aparecendo num display nunca re-layouta outro (#11).
    private func checkFullscreen() {
        guard !lockScreenActive else { return }   // no lock a ilha fica visível; reavalia no unlock
        guard Date() >= unlockGraceUntil else { return }   // logo após o unlock o frontmost ainda é o loginwindow
        for screen in NSScreen.screens {
            let id = screen.coveDisplayID
            guard let panel = panels[id] else { continue }
            let hide = coordinator.config.hideInFullscreen && frontmostIsFullscreen(on: screen)
            guard hide != (hiddenForFullscreen[id] ?? false) else { continue }
            hiddenForFullscreen[id] = hide
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = hide ? 0 : 1
            }
        }
    }

    /// Assinatura pura da config de telas atual (id + frame + notch).
    private func currentSignature() -> String {
        let screens = ScreenSignature.make(NSScreen.screens.map { s in
            (id: s.coveDisplayID, frame: s.frame, notch: Self.notchRect(on: s).rect)
        })
        // política de display entra na assinatura: mudar displayOn/overrides
        // nas Configurações precisa reconstruir os painéis mesmo sem evento de tela
        let overrides = coordinator.config.displayOverrides
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return "\(screens)#\(coordinator.config.displayOn)#\(overrides)#\(coordinator.config.simulatedNotchOnExternal)"
    }

    /// Debounce de 500ms: agrupa uma rajada de eventos (wake + reconexão de
    /// display costumam disparar juntos) num único `reload()` (#1).
    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    /// Geometria do notch da tela: real (safeArea) ou simulado (topo centro).
    static func notchRect(on screen: NSScreen) -> (rect: NSRect, simulated: Bool) {
        let f = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let rect = NSRect(x: f.minX + left.maxX, y: f.maxY - screen.safeAreaInsets.top,
                              width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            return (rect, false)
        }
        // sem notch: simula um top-centro nas medidas do notch real (220×38 lógicos)
        let w: CGFloat = 220, h: CGFloat = 32
        return (NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h), true)
    }

    /// Baixa o nível dos painéis pra `.floating` enquanto algo do sistema
    /// (menu, QuickLook, share picker) precisa nascer por cima da ilha —
    /// contador, não booleano: dois chamadores concorrentes só devolvem
    /// `.screenSaver` quando o último soltar (substitui `setPanelsLevel`, #18).
    func pushLoweredLevel() {
        loweredLevelCount += 1
        if loweredLevelCount == 1 { applyLevel() }
    }

    /// Nível durante ARRASTO de arquivo: acima da barra de menus (a ilha mora nela —
    /// em .floating a barra vira o alvo e o drag "sai" do painel) e abaixo do teto
    /// que o drag manager ainda enxerga (.screenSaver não é encontrado).
    static let dragLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
    private var draggingLevel = false
    func setDragLevel(_ on: Bool) {
        guard on != draggingLevel else { return }
        draggingLevel = on
        guard loweredLevelCount == 0 else { return }   // menu/QuickLook aberto manda
        applyLevel()
    }

    /// Contraparte de `pushLoweredLevel()`. Nunca deixa o contador negativo.
    func popLoweredLevel() {
        guard loweredLevelCount > 0 else { return }
        loweredLevelCount -= 1
        if loweredLevelCount == 0 { applyLevel() }
    }

    func reload() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let sig = currentSignature()
            guard sig != lastSignature else { return }
            hide()
            show()
        }
    }

    /// sharingType conforme config (esconder de capturas de tela).
    func applySharing() {
        let hide = coordinator.config.hideFromCapture
        panels.values.forEach { $0.sharingType = hide ? .none : .readOnly }
        lockWidgets?.applySharing(hide: hide)   // linha de widgets do lock segue a ilha
    }

    private func wantsPanel(on screen: NSScreen) -> Bool {
        let builtin = screen.safeAreaInsets.top > 0
        let uuid = DisplayIdentity.current(for: screen.coveDisplayID).uuid
        return DisplayPolicy.wantsPanel(uuid: uuid, isBuiltin: builtin,
                                         global: coordinator.config.displayOn,
                                         overrides: coordinator.config.displayOverrides)
    }

    func show() {
        // detector de "jiggle": arraste global com arquivo no pasteboard de
        // drag entrando nos 60pt do topo da tela → abre a ilha na Cesta.
        lastDragCount = NSPasteboard(name: .drag).changeCount   // baseline: drag antigo não conta
        if mouseMonitor == nil {
            // Painel FIXO (760×300) — nada de resize durante animação (salto). Fora da ilha o
            // painel ignora o mouse (cliques caem no app de baixo); aceita quando o cursor
            // está sobre a ilha, com a ilha aberta, ou durante um ARRASTO de arquivo (senão
            // `ignoresMouseEvents` também descarta o destino de drop).
            let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: kinds) { [weak self] ev in
                Task { @MainActor in self?.handleGlobalMouse(ev) }
            }
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] ev in
                Task { @MainActor in self?.updateMousePassthrough() }
                return ev
            }
            // o sink de `$isExpanded/$showActions/$dragActive` vive no `init`
            // (uma vez) — aqui acumulava um por `reload()`.
        }
        // ilha PRIMÁRIA (destino de pedidos sem `displayID`, ex.: media/ambient):
        // o notch de verdade se existir, senão a 1ª tela com painel (#30).
        let candidateScreens = NSScreen.screens.filter(wantsPanel(on:))
        let primaryDisplayID = candidateScreens.first(where: { $0.safeAreaInsets.top > 0 })?.coveDisplayID
            ?? candidateScreens.first?.coveDisplayID
        for screen in NSScreen.screens {
            guard wantsPanel(on: screen) else { continue }
            let displayID = screen.coveDisplayID
            let (notch, simulated) = Self.notchRect(on: screen)
            if simulated, !coordinator.config.simulatedNotchOnExternal { continue }
            // painel maior que o notch: dá área pro estado expandido crescer
            let panelW = Self.panelSize.width, panelH = Self.panelSize.height   // margem pra sombra (r18+y8) nunca cortar
            let frame = NSRect(x: notch.midX - panelW / 2, y: notch.maxY - panelH,
                               width: panelW, height: panelH)
            let panel = KeyablePanel(contentRect: frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            // .screenSaver: fixo na troca de mesa (não desliza com o Space, como a barra de menu).
            // Se um pushLoweredLevel() estava pendente (ex.: reload() no meio de um
            // menu/QuickLook aberto), o painel recriado nasce já em .floating.
            panel.level = desiredLevel
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.appearance = NSAppearance(named: .darkAqua)   // ilha preta: glass/menus sempre dark
            panel.hasShadow = false
            panel.isMovable = false
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
            let hosting = NSHostingView(rootView: NotchView(
                coordinator: coordinator, notchSize: notch.size, simulated: simulated,
                displayID: displayID, isPrimary: displayID == primaryDisplayID))
            hosting.frame = container.bounds
            hosting.autoresizingMask = [.width, .height]
            container.addSubview(hosting)
            let host = DropHostView(frame: container.bounds)   // overlay de drop, acima do SwiftUI
            host.autoresizingMask = [.width, .height]
            host.isDragActive = { [weak self] in self?.coordinator.dragActive ?? false }
            container.addSubview(host, positioned: .above, relativeTo: hosting)
            panel.contentView = container
            panel.registerForDraggedTypes([.fileURL])   // registro no nível da JANELA (drag manager)
            host.onDrop = { [weak self] urls in self?.coordinator.handleFileDrop(urls) }
            host.onDragEnter = { [weak self] in
                guard let self else { return }
                // já expandida numa página que aceita arquivos (Converter): não troca de página
                if !(coordinator.isExpanded && coordinator.currentDroplet == .converter) {
                    coordinator.requestShowDroplet(.shelf)
                }
            }
            host.isInsideIsland = { [weak self, weak host] p in
                guard let self, let host else { return true }
                let f = coordinator.islandFrames[displayID] ?? .zero
                guard f != .zero else { return true }  // ainda não medida: falha aberto na 1ª medição
                // NSView.draggingLocation é y-up (origem embaixo); `.global` do SwiftUI hospedado é y-down
                let flipped = CGPoint(x: p.x, y: host.bounds.height - p.y)
                return f.contains(flipped)
            }
            panel.ignoresMouseEvents = ProcessInfo.processInfo.environment["COVE_NOPASS"] == nil
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            // reload() no meio de um lock (wake + reconexão de tela): o painel
            // novo entra no space SkyLight na hora, já ordenado (windowNumber válido).
            if lockScreenActive, let bridge = LockScreenBridge.shared {
                panel.ignoresMouseEvents = true
                bridge.delegate(panel)
            }
            panels[displayID] = panel
        }
        applySharing()
        lastSignature = currentSignature()
        // reload no meio do lock (ou preview): os painéis de widgets foram
        // fechados no `hide()` — renascem nas telas que acabaram de ganhar ilha.
        if lockScreenActive {
            syncLockWidgets(bridge: LockScreenBridge.shared)
        } else if NotchCoordinator.previewLock, coordinator.isScreenLocked {
            syncLockWidgets(bridge: nil)
        }
    }

    func hide() {
        dismissLockWidgets()   // desdelega + orderOut ANTES dos painéis da ilha
        if lockScreenActive, let bridge = LockScreenBridge.shared {
            panels.values.forEach { bridge.undelegate($0) }   // antes do orderOut; o flag fica
        }
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        hiddenForFullscreen.removeAll()
        hiddenBeforeLock.removeAll()
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
        dragPollTask?.cancel(); dragPollTask = nil
    }

    /// Cursor sobre a ilha deste painel? (`islandFrames[id]` é `.global` do SwiftUI,
    /// y-down; a janela é y-up — mesma conversão do `isInsideIsland` do drop.)
    private func islandContains(screenPoint: NSPoint, id: CGDirectDisplayID, panel: NSPanel) -> Bool {
        guard panel.frame.contains(screenPoint) else { return false }
        guard let f = coordinator.islandFrames[id], f != .zero else { return true }
        let p = panel.convertPoint(fromScreen: screenPoint)
        let flipped = CGPoint(x: p.x, y: (panel.contentView?.bounds.height ?? Self.panelSize.height) - p.y)
        return f.insetBy(dx: -12, dy: -12).contains(flipped)
    }

    func updateMousePassthrough() {
        if ProcessInfo.processInfo.environment["COVE_NOPASS"] != nil { return }
        if lockScreenActive {   // lock: mouse SEMPRE ignorado (loginwindow é dono do input)
            panels.values.forEach { if !$0.ignoresMouseEvents { $0.ignoresMouseEvents = true } }
            return
        }
        let loc = NSEvent.mouseLocation
        let keep = coordinator.dragActive || coordinator.isExpanded || coordinator.showActions
        for (id, panel) in panels {
            let wants = keep || islandContains(screenPoint: loc, id: id, panel: panel)
            if panel.ignoresMouseEvents == wants { panel.ignoresMouseEvents = !wants }
        }
    }

    /// Arrasto de arquivo: enquanto o botão está pressionado, sonda o pasteboard
    /// de drag a 100ms (monitores globais não são confiáveis dentro de uma sessão
    /// de drag). Com arquivo no drag → `dragActive` (painéis aceitam o drop); perto
    /// do topo (60pt) → abre a Cesta ("jiggle"). Solta → `dragActive` cai 600ms depois
    /// (tempo do `performDragOperation` chegar).
    private func handleGlobalMouse(_ ev: NSEvent) {
        switch ev.type {
        case .leftMouseDown:
            DropHostView.dlog("mouseDown loc=\(NSEvent.mouseLocation) dragCount=\(NSPasteboard(name: .drag).changeCount) last=\(lastDragCount)")
            dragPollTask?.cancel()
            dragPollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled, NSEvent.pressedMouseButtons & 1 == 1 {
                    self?.pollDrag()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        case .leftMouseUp:
            dragPollTask?.cancel(); dragPollTask = nil
            lastDragCount = NSPasteboard(name: .drag).changeCount
            if coordinator.dragActive {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(600))
                    self?.coordinator.dragActive = false
                    self?.setDragLevel(false)
                    self?.updateMousePassthrough()
                }
            }
        default:
            updateMousePassthrough()
        }
    }

    private func pollDrag() {
        let pb = NSPasteboard(name: .drag)
        DropHostView.dlog("poll count=\(pb.changeCount) last=\(lastDragCount) file=\(pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])) active=\(coordinator.dragActive)")
        guard pb.changeCount != lastDragCount,
              pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
        if !coordinator.dragActive {
            coordinator.dragActive = true
            DropHostView.dlog("drag de arquivo detectado (changeCount \(pb.changeCount))")
            setDragLevel(true)
        }
        // SÍNCRONO: durante a sessão de drag o runloop está em modo de tracking; o
        // sink de passthrough (hop pra DispatchQueue.main) é assíncrono e chegaria
        // um turno depois — o destino de drop precisa aceitar o mouse AGORA.
        guard !lockScreenActive else { return }
        for panel in panels.values where panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
        let loc = NSEvent.mouseLocation
        if ProcessInfo.processInfo.environment["COVE_NOJIGGLE"] == nil,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(loc) }),
           screen.frame.maxY - loc.y < 60,
           !(coordinator.isExpanded && coordinator.currentDroplet == .converter) {
            coordinator.requestShowDroplet(.shelf)
        }
    }

    /// Painel a focar/desfocar: o da tela sob o mouse (onde o usuário está
    /// digitando agora) — fallback pro painel expandido, senão o primeiro
    /// (dicionário sem ordem, mas nunca fica sem candidato) (#32).
    private func keyCandidatePanel() -> NSPanel? {
        if let id = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.coveDisplayID,
           let panel = panels[id] {
            return panel
        }
        if coordinator.isExpanded, let id = currentExpandedDisplayID, let panel = panels[id] {
            return panel
        }
        return panels.values.first
    }

    /// Tela cujo painel está com a ilha expandida agora, quando dá pra saber
    /// (nenhuma tela sob o mouse é o caso raro — ex.: atalho de teclado puro).
    private var currentExpandedDisplayID: CGDirectDisplayID? {
        NSScreen.screens.first { screen in
            let id = screen.coveDisplayID
            guard let panel = panels[id] else { return false }
            return panel.isKeyWindow
        }?.coveDisplayID
    }

    /// Dá foco de teclado ao painel da tela sob o mouse, SEM ativar o app (não
    /// rouba foco de outros apps além do painel — `.nonactivatingPanel`
    /// normalmente não vira key window).
    func makeKey() {
        keyCandidatePanel()?.makeKey()
    }

    func resignKey() {
        keyCandidatePanel()?.resignKey()
    }
}
