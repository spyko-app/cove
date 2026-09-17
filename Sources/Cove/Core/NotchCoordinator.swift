import AppKit
import Combine
import EventKit
import Foundation

/// Atividade transitória exibida no peek da ilha (estilo Dynamic Island).
enum NotchActivity: Equatable {
    case volume(Float, muted: Bool)
    case brightness(Float)
    case battery(PowerService.BatteryState)
    case lowPowerMode(Bool)
    case device(name: String, connected: Bool, battery: Int? = nil)
    case focus(Bool)
    case lock(Bool)
    case event(title: String, minutes: Int)
    case eventCountdown(title: String, start: Date, meetingURL: URL?)
    case notification(app: String, title: String)
    case track(title: String, artist: String)
    case keyboardBrightness(Float)
    case timer(label: String, remaining: Int)
    case recording(elapsed: Int)
    case screenRecording(elapsed: Int)
    case wifi(ssid: String?, connected: Bool)
    case hotspot(on: Bool)
    case drive(name: String, mounted: Bool)
    case vpn(up: Bool)
    case vpnSession(since: Date)
    case highAlert(expiresAt: Date)

    /// HUD = substitui na hora; evento = enfileira atrás do que está na tela.
    var isHUD: Bool {
        switch self {
        case .volume, .brightness, .keyboardBrightness: true
        default: false
        }
    }

    /// Janela do countdown de calendário: de T-15min até 5min após o início —
    /// pura, sem `Date()` implícito, fácil de testar com datas fixas.
    static func eventCountdownActive(now: Date, start: Date) -> Bool {
        let delta = start.timeIntervalSince(now)
        return delta <= 15 * 60 && delta >= -5 * 60
    }

    /// Progresso do ring (0 em T-15min, 1 no início) — clampado após o início.
    static func eventCountdownProgress(now: Date, start: Date) -> Double {
        let total = 15.0 * 60
        let remaining = start.timeIntervalSince(now)
        return min(max((total - remaining) / total, 0), 1)
    }
}

/// Destino de uma captura: cesta, OCR (reconhece e copia texto) ou clipboard direto (PNG).
enum CaptureDestination {
    case shelf, ocr, clipboard
}

/// Dono do estado da ilha: junta todos os serviços e publica a atividade
/// corrente com auto-dismiss (HUD curto, evento mais longo). Now playing é
/// estado persistente (asas), atividade é transitória (peek por cima).
@MainActor
final class NotchCoordinator: ObservableObject {
    /// Slot ESQUERDO da ilha (brilho) e DIREITO (volume + eventos) — podem
    /// coexistir sem sobreposição, como as duas atividades do Dynamic Island.
    @Published var leadingActivity: NotchActivity?
    @Published var trailingActivity: NotchActivity?
    /// Atividade persistente (ex.: timer rodando) — não bypassa nem some com
    /// o dismiss do trailing transitório; some por baixo/depois dele.
    @Published private(set) var ambientActivity: NotchActivity?
    @Published var config = NotchConfigStore.load()
    /// Pedido de expandir/recolher vindo de gesto (swipe vertical) ou clique.
    @Published var expandRequest: UIRequest<Bool>?
    /// Gesto vertical com a ilha aberta: +1 desce (apps), -1 sobe (mídia).
    @Published var pageRequest: UIRequest<Int>?
    /// Arraste de arquivo em andamento (jiggle detectado) — mantém a ilha aberta.
    @Published var dragActive = false
    /// Pedido de trocar pra uma página específica (ex.: jiggle mostra a Cesta).
    @Published var showDropletRequest: UIRequest<Droplet>?
    /// Arquivos soltos na ilha com o Converter aberto (o drop é AppKit no
    /// `DropHostView`; SwiftUI `.dropDestination` no hosting view roubava o drag).
    @Published var converterDropRequest: UIRequest<[URL]>?
    private var dropSeq = 0

    /// Roteia um drop de arquivos: Converter aberto → fila do Converter; senão Cesta.
    func handleFileDrop(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        if isExpanded, currentDroplet == .converter {
            dropSeq += 1
            converterDropRequest = UIRequest(seq: dropSeq, value: files)
        } else {
            shelf.add(files)
            requestShowDroplet(.shelf)
        }
    }
    /// Atalhos que falharam ao registrar no boot ou ao editar (já em uso por
    /// outro app/sistema) — Ajustes › Droplets marca em vermelho (#40).
    @Published private(set) var failedHotKeys: Set<String> = []
    /// Tela bloqueada agora (espelho de `SystemEvents.isScreenLocked`). Com
    /// ela bloqueada a ilha só EXIBE (HUDs, asas de mídia, bateria): nunca
    /// expande, nem por gesto nem por alerta — o loginwindow é dono do input.
    @Published private(set) var isScreenLocked = false
    /// `COVE_PREVIEW_LOCK=1`: força `isScreenLocked` (cadeado na ilha + painel
    /// de widgets no desktop) SEM delegar nada ao space SkyLight — captura de
    /// tela sem bloquear a máquina de verdade. `NotchPanelController` lê.
    static let previewLock = ProcessInfo.processInfo.environment["COVE_PREVIEW_LOCK"] == "1"

    /// Grade de Ações rápidas (ex-Ring) mostrada DENTRO da ilha expandida,
    /// no lugar da página do droplet atual — `NotchView` troca de conteúdo
    /// quando isto liga/desliga; nunca sobrevive a colapsar a ilha.
    @Published var showActions = false
    /// Vista expandida da atividade (F1/F2 do ciclo 8 — 4 regiões + ações).
    /// Sempre dentro da ilha aberta, no lugar da página do droplet.
    @Published var showActivityExpanded = false
    /// Atividade congelada enquanto o card expandido está aberto — o peek
    /// transitório morre em 3s, o card vive 6s (não pode esvaziar no meio).
    @Published private(set) var expandedActivity: NotchActivity?
    /// Aberta por gesto do dono (toque longo) — só nesse caso o painel pega
    /// foco de teclado (pro Esc). Alerta automático nunca rouba o teclado.
    @Published private(set) var activityExpandedFromGesture = false
    /// `kindKey` do último alerta que já abriu o card sozinho — só reseta
    /// quando o tipo deixa de alertar (bateria 10→9→8% não reabre 3 vezes).
    private var lastAlertedKey: String?
    private var activityExpandedDismiss: Task<Void, Never>?
    private var requestSeq = 0

    let shelf = ShelfStore()
    let clipboard: ClipboardStore!
    let linkPreviews = LinkPreviewCache()
    let spotlight = SpotlightSearch()
    let timers = TimerService()
    let highAlert = HighAlert()
    private let hotKeyCenter = HotKeyCenter.shared
    private static let ringHotKeyID: UInt32 = 1
    private static let dropletHotKeyBase: UInt32 = 100
    let ocr = OCRService()
    let voice = VoiceMemoService()
    let screenRecorder = ScreenRecorder()
    /// Fonte única de verdade da captura em andamento — cartões só leem, nunca simulam.
    @Published private(set) var isCapturing = false

    /// Compat: atividade "principal" = trailing, senão leading.
    var activity: NotchActivity? { trailingActivity ?? leadingActivity }

    let media = MediaRemoteService()
    let lyrics = LyricsService()
    /// `lazy`: só instancia na 1ª vez que a ilha expande na página de mídia —
    /// não no lançamento do app. O TCC de Automation não dispara na construção
    /// (sem `SBApplication` no `init` do `PlayerBridge`), só no 1º `refresh()`
    /// via `startPolling()` (chamado por `updatePlayerBridgePolling()` abaixo).
    lazy var playerBridge: PlayerBridge = {
        let bridge = PlayerBridge()
        bridge.nowPlayingTitleProvider = { [weak self] in self?.media.nowPlaying.title }
        return bridge
    }()
    let calendar = CalendarService()
    let weather = WeatherService()
    let waveform: WaveformService? = WaveformService()
    let notifications = NotificationMirror()
    /// `lazy`: só instancia quando a página Sistema aparece pela 1ª vez —
    /// amostragem só roda enquanto a página está visível (start/stop no onAppear/onDisappear).
    lazy var systemStats = SystemStats()
    /// `lazy`: só resolve `Config.obsidianVaultPath` (AppSupport ou vault) quando
    /// a página Notas aparece pela 1ª vez.
    lazy var notesStore: NotesStore = {
        let store = NotesStore(vaultPath: config.obsidianVaultPath)
        notesStoreIfLoaded = store
        return store
    }()
    /// Acesso sem disparar a instanciação `lazy` — usado pra saber se já dá
    /// pra chamar `reconfigure(vaultPath:)` quando o vault muda em Settings.
    private(set) var notesStoreIfLoaded: NotesStore?
    /// `lazy`: só instancia quando a página Converter aparece pela 1ª vez.
    lazy var converter = Converter()
    lazy var emojiStore = EmojiStore()
    let outputs = OutputDevices()
    private let audio = AudioService()
    private let systemEvents = SystemEvents()
    /// Entradas dos widgets da tela de bloqueio (`LockWidgetsController`) —
    /// os serviços são privados, só o publisher sai.
    var focusActivePublisher: AnyPublisher<Bool, Never> { systemEvents.$isFocusActive.eraseToAnyPublisher() }
    var batteryPublisher: AnyPublisher<PowerService.BatteryState?, Never> { power.$state.eraseToAnyPublisher() }
    private let hudSuppressor = HUDSuppressor()
    private let keyTap = MediaKeyTap()
    private let brightness = BrightnessWatcher()
    private let backlight = KeyboardBacklight()
    private var activityQueue = ActivityQueue()
    private let power = PowerService()
    private var networkHUD: NetworkHUDService!
    private var vpnMonitor: VPNMonitor!
    /// false quando o CoreWLAN recusou o monitoramento de Wi-Fi no boot —
    /// espelhado uma vez no init (não muda depois) pra UI de Ajustes avisar.
    @Published private(set) var wifiMonitoringAvailable = true
    private var bluetooth: BluetoothService?
    private var leadingDismiss: Task<Void, Never>?
    private var trailingDismiss: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    /// Captura em andamento — um clique por vez (Droppy §4 #2: preso ao lifecycle de quem pediu).
    private var captureTask: Task<Void, Never>?
    /// Guardado pra não deixar o `NSColorSampler` ser desalocado antes do callback.
    private var colorSampler: NSColorSampler?
    /// Reavalia a janela do countdown de calendário (entra/sai de T-15min e
    /// T+5min) independente de `calendar.next` mudar — o próprio relógio anda.
    private var ambientTick: Timer?

    init() {
        PasteAtCursor.startTrackingFrontmost()
        let initialConfig = NotchConfigStore.load()
        clipboard = ClipboardStore(limit: initialConfig.clipboardLimit, retentionDays: initialConfig.clipboardRetentionDays)
        PasteAtCursor.onOwnWrite = { [weak self] in self?.clipboard.acknowledgeOwnWrite() }
        audio.onVolumeChange = { [weak self] v, muted in
            guard let self, config.showVolumeHUD else { return }
            show(.volume(v, muted: muted), for: config.hudDuration)
        }
        brightness.onBrightnessChange = { [weak self] v in
            guard let self, config.showBrightnessHUD else { return }
            show(.brightness(v), for: config.hudDuration)
        }
        power.onBatteryEvent = { [weak self] state in
            guard let self, config.showBatteryEvents else { return }
            show(.battery(state), for: config.eventDuration)
            if !state.onAC, state.percent <= config.lowBatteryThreshold, config.eventSounds {
                SystemEvents.playSound("low-battery")
            }
        }
        power.onLowPowerMode = { [weak self] on in
            guard let self, config.notifyOnLowPowerMode else { return }
            show(.lowPowerMode(on), for: config.eventDuration)
            if config.eventSounds { SystemEvents.playSound("low-power") }
        }
        networkHUD = NetworkHUDService(isWifiHUDEnabled: { [weak self] in self?.config.showWifiHUD ?? false })
        wifiMonitoringAvailable = networkHUD.wifiMonitoringAvailable
        networkHUD.onActivity = { [weak self] activity in
            guard let self else { return }
            switch activity {
            case .wifi, .hotspot:
                guard config.showWifiHUD else { return }
            case .drive:
                guard config.showDriveHUD else { return }
            default:
                break
            }
            show(activity, for: config.eventDuration)
            if config.eventSounds { SystemEvents.playSound("device") }
        }
        vpnMonitor = VPNMonitor()
        vpnMonitor.onEvent = { [weak self] event in
            guard let self else { return }
            updateAmbientActivity(timerSession: timers.session)
            guard config.showVPNHUD else { return }
            show(.vpn(up: event == .up), for: config.eventDuration)
            if config.eventSounds { SystemEvents.playSound("device") }
        }
        // Bluetooth ATRASADO e fora do caminho de abertura: TCC do BT exige
        // bundle .app com plist real (embutido via -sectcreate NÃO passa —
        // crash provado) e o prompt não pode segurar a criação dos painéis.
        if AppEnvironment.isBundledApp, config.onboardingDone {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.startBluetooth()
            }
        }
        timers.onFinished = { [weak self] label in
            guard let self else { return }
            show(.event(title: "\(label) terminou", minutes: 0), for: config.eventDuration)
            if config.eventSounds { SystemEvents.playSound("chime") }
            if label == "Pomodoro" { timers.start(label: "Pausa", seconds: TimerService.pomodoroBreak) }
        }
        timers.$session
            .removeDuplicates()
            .sink { [weak self] session in
                guard let self else { return }
                updateAmbientActivity(timerSession: session)
            }
            .store(in: &cancellables)
        highAlert.lastDuration = HighAlert.Duration(rawValue: initialConfig.highAlertDuration) ?? .infinite
        highAlert.$isOn
            .combineLatest(highAlert.$expiresAt)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] _, _ in
                guard let self else { return }
                updateAmbientActivity(timerSession: timers.session)
            }
            .store(in: &cancellables)
        voice.$isRecording
            .combineLatest(voice.$elapsed)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] _, _ in
                guard let self else { return }
                updateAmbientActivity(timerSession: timers.session)
            }
            .store(in: &cancellables)
        screenRecorder.$isRecording
            .combineLatest(screenRecorder.$elapsed)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] _, _ in
                guard let self else { return }
                updateAmbientActivity(timerSession: timers.session)
            }
            .store(in: &cancellables)
        // gravação que CAI com erro sai do ambiente (isRecording=false) antes
        // de `maybeAutoExpand` vê-la — o alerta vem do próprio erro (#F1).
        screenRecorder.$lastError
            .removeDuplicates()
            .sink { [weak self] err in
                guard let self, err != nil else { return }
                maybeAutoExpand(.screenRecording(elapsed: screenRecorder.elapsed))
            }
            .store(in: &cancellables)
        calendar.$next
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                updateAmbientActivity(timerSession: timers.session)
            }
            .store(in: &cancellables)
        // Cesta reage à config sem reler o JSON do disco a cada 2s (#35).
        shelf.bindConfig($config)
        wireSystemEvents()
        clipboard.startWatching()
        registerRingHotKey()
        registerAllDropletHotKeys()
        if config.showWeather { weather.start() }
        updateAmbientTickScheduling()
    }

    private static func dropletHotKeyID(_ d: Droplet) -> UInt32? {
        guard let index = Droplet.allCases.firstIndex(of: d) else { return nil }
        return dropletHotKeyBase + UInt32(index)
    }

    /// Todos os combos já em uso (ring + droplets), pra detectar conflito
    /// antes de registrar um novo — nunca pisa num atalho já reivindicado.
    private func activeCombos(excluding excludedID: UInt32?) -> [(id: UInt32, combo: HotKeyCombo)] {
        var pairs: [(id: UInt32, combo: HotKeyCombo)] = []
        if Self.ringHotKeyID != excludedID, let combo = HotKeyCombo.parse(config.ringHotKey) {
            pairs.append((Self.ringHotKeyID, combo))
        }
        for d in Droplet.allCases {
            guard let id = Self.dropletHotKeyID(d), id != excludedID else { continue }
            guard let s = config.dropletHotKeys[d.rawValue], let combo = HotKeyCombo.parse(s) else { continue }
            pairs.append((id, combo))
        }
        return pairs
    }

    private func registerAllDropletHotKeys() {
        for d in Droplet.allCases {
            registerDropletHotKey(d, notifyOnFailure: false)
        }
    }

    @discardableResult
    private func registerDropletHotKey(_ d: Droplet, notifyOnFailure: Bool) -> Bool {
        guard let id = Self.dropletHotKeyID(d) else { return false }
        guard let s = config.dropletHotKeys[d.rawValue], !s.isEmpty else {
            hotKeyCenter.unregister(id: id)
            failedHotKeys.remove(d.rawValue)
            return true
        }
        guard let combo = HotKeyCombo.parse(s) else {
            hotKeyCenter.unregister(id: id)
            failedHotKeys.insert(d.rawValue)
            return false
        }
        // some ANTES de checar conflito — nunca deixa o registro antigo vivo
        // se o combo novo for rejeitado (Ciclo7 T11 review).
        hotKeyCenter.unregister(id: id)
        var pairs = activeCombos(excluding: id)
        pairs.append((id, combo))
        if !HotKeyRegistryPlanner.conflicts(in: pairs).isEmpty {
            if notifyOnFailure { notify(app: "Atalhos", title: "\(s) já está em uso") }
            failedHotKeys.insert(d.rawValue)
            return false
        }
        let ok = hotKeyCenter.register(id: id, combo: combo) { [weak self] in
            guard let self else { return }
            self.toggleDroplet(d)
        }
        if ok {
            failedHotKeys.remove(d.rawValue)
        } else {
            // registro no boot é silencioso (`notifyOnFailure: false`), mas
            // sempre fica marcado — Ajustes › Droplets mostra em vermelho (#40).
            failedHotKeys.insert(d.rawValue)
            if notifyOnFailure { notify(app: "Atalhos", title: "Atalho \(s) indisponível") }
        }
        return ok
    }

    /// Atalho de droplet: abre na página se fechada/noutra página; se já
    /// aberta nessa mesma página, recolhe (toggle) — diferente do jiggle,
    /// que só abre (`requestShowDroplet`).
    private func toggleDroplet(_ d: Droplet) {
        if isExpanded, currentDroplet == d {
            requestExpand(false)
        } else {
            requestShowDroplet(d)
        }
    }

    /// Atividade ambiente (persistente): gravação (tela > voz) > countdown de
    /// calendário > timer > sessão de VPN quando coexistem (C3) — nunca oculta
    /// uma pela outra silenciosamente.
    private func updateAmbientActivity(timerSession: TimerService.Session?) {
        let new: NotchActivity?
        if screenRecorder.isRecording {
            new = .screenRecording(elapsed: screenRecorder.elapsed)
        } else if voice.isRecording {
            new = .recording(elapsed: voice.elapsed)
        } else if config.showCalendar, let ev = calendar.next,
                  NotchActivity.eventCountdownActive(now: Date(), start: ev.start) {
            new = .eventCountdown(title: ev.title, start: ev.start, meetingURL: ev.meetingURL)
        } else if let s = timerSession, s.isRunning {
            new = .timer(label: s.label, remaining: s.remaining)
        } else if highAlert.isOn, let expiresAt = highAlert.expiresAt {
            new = .highAlert(expiresAt: expiresAt)
        } else if config.showVPNHUD, let since = vpnMonitor?.sessionStart {
            new = .vpnSession(since: since)
        } else {
            new = nil
        }
        if ambientActivity != new { ambientActivity = new }
        // card aberto sobre a MESMA atividade: atualiza o payload (senão o
        // mm:ss do timer/gravação congela no snapshot por 6 s).
        if showActivityExpanded, let new, new.kindKey == expandedActivity?.kindKey {
            expandedActivity = new
        }
        // Atividade sumindo por um instante NÃO reabre a trava: a chave só
        // limpa quando a mesma atividade volta sem alertar (maybeAutoExpand)
        // ou no snooze de evento (snoozeEvent) — senão bateria 10→9→8 %
        // reabria o card (#3).
        if let new { maybeAutoExpand(new) }
        updateAmbientTickScheduling()
    }

    /// `ambientTick` só existe enquanto algo depende dele reavaliar sozinho
    /// (calendário/VPN mudam com o relógio, sem evento próprio) — sem isso é
    /// um timer de 15s rodando pra sempre à toa (#33). Reavaliado a cada
    /// mudança de estado ambiente e a cada `updateConfig`.
    private func updateAmbientTickScheduling() {
        let needed = config.showCalendar || config.showVPNHUD || timers.session != nil || highAlert.isOn
        if needed {
            guard ambientTick == nil else { return }
            ambientTick = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.updateAmbientActivity(timerSession: self.timers.session)
                }
            }
        } else {
            ambientTick?.invalidate()
            ambientTick = nil
        }
    }

    /// Chave de `failedHotKeys` pro atalho de Ações rápidas (não é um `Droplet`).
    static let ringHotKeyFailureKey = "__ring__"

    private func registerRingHotKey(notifyOnFailure: Bool = false) {
        guard let combo = HotKeyCombo.parse(config.ringHotKey) else { return }
        var pairs = activeCombos(excluding: Self.ringHotKeyID)
        pairs.append((Self.ringHotKeyID, combo))
        if !HotKeyRegistryPlanner.conflicts(in: pairs).isEmpty {
            if notifyOnFailure { notify(app: "Atalhos", title: "\(config.ringHotKey) já está em uso") }
            failedHotKeys.insert(Self.ringHotKeyFailureKey)
            return
        }
        let ok = hotKeyCenter.register(id: Self.ringHotKeyID, combo: combo) { [weak self] in
            self?.toggleActions()
        }
        guard !ok else {
            failedHotKeys.remove(Self.ringHotKeyFailureKey)
            return
        }
        // registro no boot é silencioso, mas sempre fica marcado (#40).
        failedHotKeys.insert(Self.ringHotKeyFailureKey)
        if notifyOnFailure {
            notify(app: "Ring", title: "Atalho \(config.ringHotKey) indisponível")
        } else {
            FileHandle.standardError.write(Data("Cove: atalho \(config.ringHotKey) indisponível\n".utf8))
        }
    }

    /// Onboarding: usuário pediu Acessibilidade explicitamente.
    func startKeyTap(prompt: Bool) {
        keyTap.start(prompt: prompt)
        brightness.setSlowMode(keyTap.active)
    }

    func startBluetooth() {
        guard bluetooth == nil, AppEnvironment.isBundledApp else { return }
                let bt = BluetoothService()
                bt.onDeviceEvent = { [weak self] name, connected in
                    Task { @MainActor in
                        guard let self, self.config.showBluetoothEvents else { return }
                        self.show(.device(name: name, connected: connected),
                                  for: self.config.eventDuration)
                        if connected, self.config.eventSounds { SystemEvents.playSound("device") }
                        guard connected else { return }
                        // bateria demora a aparecer no registry — busca após 2s
                        try? await Task.sleep(for: .seconds(2))
                        if let b = BluetoothService.appleDeviceBattery(named: name),
                           let pct = b.left ?? b.right ?? b.case_ {
                            self.show(.device(name: name, connected: true,
                                              battery: min(pct, b.right ?? pct)),
                                      for: self.config.eventDuration)
                        }
                    }
                }
                self.bluetooth = bt
    }

    private func wireSystemEvents() {
        systemEvents.onFocusChange = { [weak self] on in
            guard let self, config.showFocusEvents else { return }
            show(.focus(on), for: config.eventDuration)
        }
        // estado de bloqueio: espelha e, ao bloquear, recolhe tudo que estava
        // aberto (card de atividade, grade de ações) — na tela de bloqueio só
        // existe a ilha fechada. `NotchView` também recolhe por tela.
        systemEvents.$isScreenLocked
            .removeDuplicates()
            .sink { [weak self] locked in
                guard let self else { return }
                // preview entra AQUI (não no init): o `@Published` do serviço
                // emite `false` na assinatura e sobrescreveria um valor do init.
                isScreenLocked = locked || Self.previewLock
                if locked {
                    showActions = false
                    closeActivityExpanded()
                    // notificação já no peek (ou enfileirada) no instante do
                    // lock: derruba — mesma regra do `show()`. Cancela o dismiss
                    // antes de zerar (o Task antigo não pode acordar e re-mostrar).
                    if let t = trailingActivity,
                       !LockScreenPolicy.allowsPeek(kindKey: t.kindKey, locked: true) {
                        trailingDismiss?.cancel()
                        trailingActivity = nil
                    }
                    activityQueue.removeAll(kindKey: "notification")
                    // drena a fila na hora: evento/bateria enfileirados atrás da notificação não podem ficar presos
                    if let next = activityQueue.next(now: Date()) { show(next.activity, for: next.duration) }
                } else {
                    // alerta que chegou bloqueado NÃO queimou `lastAlertedKey`
                    // (`maybeAutoExpand`): reavalia agora, depois de o painel
                    // sair do space do lock — o sink do `NotchPanel` roda no hop
                    // pra `DispatchQueue.main`, já enfileirado antes deste bloco.
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !isScreenLocked else { return }
                        updateAmbientActivity(timerSession: timers.session)
                        if let a = activityForExpansion { maybeAutoExpand(a) }
                    }
                }
            }
            .store(in: &cancellables)
        systemEvents.onScreenLock = { [weak self] locked in
            guard let self, config.showLockEvents else { return }
            show(.lock(locked), for: config.eventDuration)
            if config.eventSounds { SystemEvents.playSound(locked ? "lock" : "unlock") }
        }
        systemEvents.onHourlyChime = { [weak self] in
            guard let self, config.hourlyChime else { return }
            if config.eventSounds { SystemEvents.playSound("chime") }
        }
        calendar.selectedCalendarIDs = config.calendarIDs
        calendar.onTimeToLeave = { [weak self] event in
            guard let self, config.showCalendar else { return }
            let mins = max(Int(event.start.timeIntervalSinceNow / 60), 0)
            show(.event(title: event.title, minutes: mins), for: config.eventDuration * 2)
            if config.eventSounds { SystemEvents.playSound("directions") }
        }
        if config.suppressSystemHUD { hudSuppressor.enable() }
        // teclas de mídia: consumimos e aplicamos nós — mata o HUD do Dock
        // (macOS 26). Atrasado: prompt de Acessibilidade fora da abertura.
        keyTap.onVolumeKey = { [weak self] delta, mute in
            guard let self else { return }
            if mute {
                audio.setMuted(!audio.muted)
            } else {
                audio.setVolume(audio.volume + Float(delta) / 16)
            }
            show(.volume(audio.volume, muted: audio.muted), for: config.hudDuration)
            if config.eventSounds { SystemEvents.playSound("volume") }
        }
        keyTap.onKeyboardBrightnessKey = { [weak self] delta in
            guard let self, config.keyboardBrightnessHUD, backlight.available else { return false }
            let v = min(max(backlight.brightness + Float(delta) / 16, 0), 1)
            guard backlight.set(v) else { return false }
            show(.keyboardBrightness(v), for: config.hudDuration)
            return true
        }
        keyTap.onBrightnessKey = { [weak self] delta in
            guard let self else { return }
            let v = min(max((BrightnessWatcher.read() ?? 0.5) + Float(delta) / 16, 0), 1)
            BrightnessWatcher.set(v)
            show(.brightness(v), for: config.hudDuration)
        }
        if AppEnvironment.isBundledApp, config.suppressSystemHUD {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                // re-tenta a cada 5s: o dono concede Acessibilidade com o app aberto
                for _ in 0..<120 {
                    guard let self, config.suppressSystemHUD else { return }
                    keyTap.start()
                    brightness.setSlowMode(keyTap.active)
                    if keyTap.active { return }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
        notifications.onNotification = { [weak self] note in
            guard let self, config.showNotifications else { return }
            show(.notification(app: note.app, title: note.title), for: config.eventDuration)
        }
        // waveform real liga/desliga seguindo o playback — só se já foi
        // habilitada por expansão na página de mídia (evita TCC de captura
        // de áudio sem gesto do usuário).
        media.$nowPlaying
            .map(\.isPlaying)
            .removeDuplicates()
            .dropFirst()  // nunca dispara TCC no caminho de abertura
            .sink { [weak self] playing in
                guard let self, config.liveWaveform, let wf = waveform,
                      isExpanded, currentDroplet == .media else { return }
                if playing { wf.start() } else { wf.stop() }
            }
            .store(in: &cancellables)
        // peek na troca de faixa (estilo Alcove: título aparece e recolhe)
        media.$nowPlaying
            .map(\.title)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] title in
                guard let self, config.trackChangePeek, !title.isEmpty,
                      media.nowPlaying.isPlaying else { return }
                show(.track(title: title, artist: media.nowPlaying.artist),
                     for: config.eventDuration)
            }
            .store(in: &cancellables)

        if ProcessInfo.processInfo.environment["COVE_ASK_AX"] == "1" {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.startKeyTap(prompt: true)
            }
        }
        // preview determinístico pra captura de tela
        if let kind = ProcessInfo.processInfo.environment["COVE_PREVIEW_HUD"] {
            switch kind {
            case "volume": trailingActivity = .volume(0.65, muted: false)
            case "brightness": trailingActivity = .brightness(0.8)
            case "battery": trailingActivity = .battery(.init(percent: 18, charging: false, onAC: false))
            case "device": trailingActivity = .device(name: "AirPods Pro", connected: true, battery: 72)
            case "focus": trailingActivity = .focus(true)
            case "lock": trailingActivity = .lock(true)
            case "event": trailingActivity = .event(title: "Reunião Cove", minutes: 8)
            case "notification": trailingActivity = .notification(app: "Mensagens", title: "Bora fechar a paridade?")
            default: break
            }
        }
    }

    private func show(_ a: NotchActivity, for duration: Double) {
        // tela bloqueada: notificação (remetente/corpo) nunca sobe por cima do
        // loginwindow — cobre `onNotification`, `notify(app:title:)` e o
        // re-show da fila, que passam todos por aqui.
        guard LockScreenPolicy.allowsPeek(kindKey: a.kindKey, locked: isScreenLocked) else { return }
        maybeAutoExpand(a)
        // evento chegando com outro evento diferente na tela → espera a vez (não substitui)
        guard activityQueue.decision(for: a, current: trailingActivity) == .showNow else {
            activityQueue.enqueue(a, duration: duration, now: Date())
            return
        }
        // ilha única: todo HUD/evento no mesmo slot; o mais recente substitui na hora
        trailingActivity = a
        trailingDismiss?.cancel()
        trailingDismiss = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            trailingActivity = nil
            if let next = activityQueue.next(now: Date()) {
                try? await Task.sleep(for: .milliseconds(250))
                show(next.activity, for: next.duration)
            }
        }
    }

    /// Notificação avulsa (ex.: resultado de OCR) — mesmo caminho do slot trailing.
    func notify(app: String, title: String) {
        show(.notification(app: app, title: title), for: config.eventDuration)
    }

    /// Peek de evento criado (ex.: evento em linguagem natural) — mesmo caminho do slot trailing.
    func announceEvent(title: String, minutes: Int) {
        show(.event(title: title, minutes: minutes), for: config.eventDuration)
    }

    // MARK: - Atividade expandida (F1/F2 — vista de 4 regiões do iOS 27)

    /// Estado externo que a tabela pura de `ActivityExpansion` precisa.
    func expansionContext(now: Date = Date()) -> ActivityExpansion.Context {
        ActivityExpansion.Context(now: now,
                                  timerRunning: timers.session?.isRunning ?? false,
                                  recordingFailed: screenRecorder.lastError != nil)
    }

    /// Atividade que o toque longo expandiria agora (peek ou ambiente).
    var activityForExpansion: NotchActivity? { trailingActivity ?? ambientActivity ?? leadingActivity }

    /// Abre a vista expandida com a atividade dada. Congela a atividade (o
    /// dismiss do peek não pode esvaziar o card) e arma o fechamento em 6 s.
    func openActivityExpanded(_ a: NotchActivity, onMouseDisplay: Bool = true, fromGesture: Bool = true) {
        guard !isScreenLocked else { return }   // tela bloqueada: só exibição, nunca card
        expandedActivity = a
        activityExpandedFromGesture = fromGesture
        trailingDismiss?.cancel()
        showActivityExpanded = true
        showActions = false
        // com a ilha já aberta o `setExpanded` do NotchView não roda — o
        // háptico de abertura sai daqui (nunca os dois juntos).
        if isExpanded, config.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        requestExpand(true, onMouseDisplay: onMouseDisplay)
        armActivityExpandedDismiss()
    }

    /// Toque longo na ilha fechada (só se houver atividade e a config permitir).
    func requestActivityExpanded() {
        guard config.expandActivityOnLongPress, let a = activityForExpansion else { return }
        openActivityExpanded(a)
    }

    /// Fecha sozinha em 6 s sem interação — cancelada pelo hover no card.
    func armActivityExpandedDismiss() {
        activityExpandedDismiss?.cancel()
        activityExpandedDismiss = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.closeActivityExpanded()
        }
    }

    func cancelActivityExpandedDismiss() {
        activityExpandedDismiss?.cancel()
        activityExpandedDismiss = nil
    }

    /// Fecha o card e volta pro estado FECHADO (nunca pro card de mídia).
    func closeActivityExpanded() {
        cancelActivityExpandedDismiss()
        guard showActivityExpanded else { return }
        showActivityExpanded = false
        activityExpandedFromGesture = false
        expandedActivity = nil
        trailingActivity = nil
        requestExpand(false)
    }

    /// Abre a vista expandida sozinha quando a atividade é um alerta de
    /// prioridade alta — uma vez por "episódio" (`lastAlertedKey`).
    private func maybeAutoExpand(_ a: NotchActivity) {
        guard ActivityExpansion.isAlerting(a, context: expansionContext()) else {
            if lastAlertedKey == a.kindKey { lastAlertedKey = nil }
            return
        }
        // `!isScreenLocked` ANTES de gravar a chave: alerta que chega bloqueado
        // (bateria 10 %, reunião ≤ 60 s, VPN caiu) adia pro unlock em vez de
        // queimar o episódio sem card (o guard de `openActivityExpanded` é só rede).
        guard config.expandActivityOnAlert, !showActivityExpanded, !isScreenLocked,
              lastAlertedKey != a.kindKey else { return }
        lastAlertedKey = a.kindKey
        openActivityExpanded(a, onMouseDisplay: false, fromGesture: false)
    }

    /// Executa uma ação rápida da região bottom e fecha o card (espelha o
    /// `LiveActivityIntent`: age no app, não abre uma tela nova).
    func perform(_ action: ActivityAction) {
        switch action {
        case .timerToggle:
            guard let s = timers.session else { break }
            if s.isRunning { timers.pause() } else { timers.resume() }
        case .timerStop:
            timers.stop()
        case .timerExtend(let seconds):
            timers.extend(by: seconds)
        case .highAlertToggle:
            highAlert.toggle()
        case .highAlertStop:
            highAlert.set(false)
        case .joinMeeting(let url):
            NSWorkspace.shared.open(url)
        case .openCalendar:
            NotchActions.openCalendar()
        case .snoozeEvent(let seconds):
            snoozeEvent(by: seconds)
        case .replyNotification, .openNotifications:
            closeActivityExpanded()
            requestShowDroplet(.notifications)
            return
        case .switchOutput:
            cancelActivityExpandedDismiss()
            let devices = outputs.devices
            guard !devices.isEmpty else { notify(app: "Áudio", title: "Nenhuma saída disponível"); break }
            NotchActions.popMenu(devices.map { d in
                ((d == outputs.current ? "✓ " : "   ") + d.name, { [weak self] in self?.outputs.select(d) })
            })
        case .openBatterySettings:
            guard let url = URL(string: ActivityExpansion.batterySettingsURL) else { break }
            NSWorkspace.shared.open(url)
        case .stopRecording:
            voice.stopSync()
        case .stopScreenRecording:
            stopScreenRecording()
        }
        closeActivityExpanded()
    }

    /// "Adiar 5 min": reagenda SÓ o aviso local do evento congelado — não
    /// mexe no convite do Calendário (sem escrita no EventKit).
    private func snoozeEvent(by seconds: Int) {
        guard let a = expandedActivity else { return }
        let title: String
        switch a {
        case .event(let t, _): title = t
        case .eventCountdown(let t, _, _): title = t
        default: return
        }
        lastAlertedKey = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Double(seconds)))
            guard let self else { return }
            self.show(.event(title: title, minutes: 0), for: self.config.eventDuration)
        }
    }

    /// Tela sob o mouse agora — pedidos de UI vindos de hotkey/ring/jiggle/drop
    /// miram nela (#30); `nil` quando o mouse não está sobre nenhuma tela
    /// conhecida, o que `UIRequest.targets` trata como "ilha primária".
    private func mouseDisplayID() -> CGDirectDisplayID? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.coveDisplayID
    }

    /// Clique/gesto na ilha: expandir ou recolher (NotchView consome). Mira a
    /// tela sob o mouse — cada `NotchView` ignora pedidos de outra tela (#30).
    func requestExpand(_ expand: Bool, onMouseDisplay: Bool = true) {
        if expand, isScreenLocked { return }   // bloqueada: recolher pode, abrir não
        requestSeq += 1
        expandRequest = UIRequest(seq: requestSeq, value: expand,
                                  displayID: onMouseDisplay ? mouseDisplayID() : nil)
    }

    func requestPage(_ delta: Int) {
        requestSeq += 1
        pageRequest = UIRequest(seq: requestSeq, value: delta, displayID: mouseDisplayID())
    }

    /// Pede pra mostrar uma página específica (ex.: jiggle detectado → Cesta).
    /// Droplet desligado nos Ajustes: avisa e não pede (senão o pedido fica
    /// pendurado — `NotchView` só reconhece páginas de `Droplet.pages(...)`).
    func requestShowDroplet(_ d: Droplet) {
        guard !isScreenLocked else { return }
        let hasMedia = !media.nowPlaying.title.isEmpty
        guard Droplet.pages(enabled: config.enabledDroplets, hasMedia: hasMedia).contains(d) else {
            notify(app: "Droplets", title: "\(d.title) está desligado nos Ajustes")
            return
        }
        requestSeq += 1
        showDropletRequest = UIRequest(seq: requestSeq, value: d, displayID: mouseDisplayID())
    }

    /// Cartão "Capturar": recolhe, captura no modo pedido, joga no destino pedido.
    func capture(_ mode: ScreenCapture.Mode, to destination: CaptureDestination) {
        guard captureTask == nil else { return }
        requestExpand(false)
        isCapturing = true
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            defer { self.captureTask = nil; self.isCapturing = false }
            let urls = await ScreenCapture.capture(mode)
            guard let url = urls.first else { return }
            switch destination {
            case .shelf:
                self.shelf.add(urls)
                self.requestShowDroplet(.shelf)
                if self.config.openEditorAfterCapture, url.pathExtension.lowercased() == "png" {
                    CaptureEditorManager.shared.open(image: url) { [weak self] edited in
                        self?.shelf.add([edited])
                    }
                }
            case .ocr:
                guard let texto = try? await self.ocr.recognize(url), !texto.isEmpty else {
                    self.notify(app: "OCR", title: "Nenhum texto reconhecido")
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(texto, forType: .string)
                self.notify(app: "OCR", title: "\(texto.count) caracteres copiados")
            case .clipboard:
                guard let data = try? Data(contentsOf: url) else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(data, forType: .png)
                self.notify(app: "Captura", title: "Copiada pro clipboard")
            }
        }
    }

    /// Cartão "Capturar": recolhe, captura região, joga na cesta.
    func captureToShelf() {
        capture(.region, to: .shelf)
    }

    /// Cartão "Capturar" (menu de modo): grava a tela inteira até `stopScreenRecording()`.
    func startScreenRecording() {
        guard !screenRecorder.isRecording else { return }
        requestExpand(false)
        Task { await screenRecorder.start() }
    }

    /// Para a gravação em andamento e joga o arquivo na cesta.
    func stopScreenRecording() {
        guard screenRecorder.isRecording else { return }
        Task { @MainActor [weak self] in
            guard let self, let url = await self.screenRecorder.stop() else { return }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs?[.size] as? Int
            let sizeLabel = size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""
            self.shelf.add([url])
            self.notify(app: "Gravação", title: "\(ScreenRecorder.formatElapsed(self.screenRecorder.elapsed)) · \(sizeLabel)")
        }
    }

    /// Cartão "OCR": recolhe, captura região, reconhece texto e copia pro clipboard.
    func captureForOCR() {
        capture(.region, to: .ocr)
    }

    /// Conta-gotas de cor: hex `#RRGGBB` sRGB direto pro clipboard.
    func pickColor() {
        requestExpand(false)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            let sampler = NSColorSampler()
            self.colorSampler = sampler
            let color = await sampler.sample()
            self.colorSampler = nil
            guard let color, let srgb = color.usingColorSpace(.sRGB) else { return }
            let r = Int(round(srgb.redComponent * 255))
            let g = Int(round(srgb.greenComponent * 255))
            let b = Int(round(srgb.blueComponent * 255))
            let hex = String(format: "#%02X%02X%02X", r, g, b)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(hex, forType: .string)
            self.notify(app: "Cor", title: hex)
        }
    }

    /// Hotkey/botão de "Ações rápidas": abre a ilha na grade de ações se
    /// fechada, ou fecha os dois juntos se já aberta — nunca deixa a grade
    /// visível com a ilha colapsada nem vice-versa.
    func toggleActions() {
        guard !isScreenLocked else { return }   // senão a grade ligaria com a ilha fechada
        if showActions {
            showActions = false
            requestExpand(false)
        } else {
            requestExpand(true)
            showActions = true
        }
    }

    /// Executa uma ação da grade de Ações rápidas configurável. Alvo ausente (app desinstalado,
    /// Atalho apagado) nunca trava o painel — só avisa via `notify` (lição Droppy).
    func perform(_ action: RingAction) {
        switch action {
        case .droplet(let d): requestShowDroplet(d)
        case .capture(let mode): capture(mode ?? .region, to: .shelf)
        case .ocr: captureForOCR()
        case .color: pickColor()
        case .screenRecord:
            screenRecorder.isRecording ? stopScreenRecording() : startScreenRecording()
        case .pomodoro: timers.start(label: "Pomodoro", seconds: TimerService.pomodoroWork)
        case .highAlert: highAlert.toggle()
        case .app(let bundleID):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                notify(app: "Ring", title: "App não encontrado")
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .shortcut(let name):
            runShortcut(name)
        }
    }

    /// `/usr/bin/shortcuts run <nome>` fora da main thread; stderr vira `notify` se falhar.
    private func runShortcut(_ name: String) {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            let errPipe = Pipe()
            process.standardError = errPipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    await MainActor.run { [weak self] in
                        self?.notify(app: "Ring", title: message.isEmpty ? "Atalho \"\(name)\" não encontrado" : message)
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.notify(app: "Ring", title: "Atalho \"\(name)\" não encontrado")
                }
            }
        }
    }

    /// Painel precisa saber se está aberta pra rotear o gesto vertical.
    @Published var isExpanded = false {
        didSet {
            updatePlayerBridgePolling()
            updateWaveformForExpansion()
            requestCalendarAccessIfNeeded()
        }
    }

    /// Primeira vez que a ilha expande com o widget de calendário ligado —
    /// pede TCC do Calendário aqui, nunca no boot (item 1 da auditoria).
    private func requestCalendarAccessIfNeeded() {
        // atividade expandida (sobretudo a automática por alerta) não é gesto
        // do dono — nunca dispara o prompt do Calendário (item 1 da auditoria).
        guard isExpanded, !showActivityExpanded, config.showCalendar,
              EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        Task { @MainActor [weak self] in
            await self?.calendar.requestAccessIfNeeded()
        }
    }
    /// Droplet visível agora (NotchView atualiza a cada troca de página); nil recolhida.
    /// O monitor de scroll usa pra decidir se deixa o evento passar pro conteúdo (C1).
    @Published var currentDroplet: Droplet? {
        didSet { updatePlayerBridgePolling(); updateWaveformForExpansion() }
    }

    private var waveformStopTask: Task<Void, Never>?

    /// Liga a captação real da waveform só quando a ilha está expandida na
    /// página de mídia (gesto do usuário) — TCC de áudio nunca dispara sozinha.
    /// Desliga com atraso de 60s ao recolher, pra não cortar no meio de um scroll rápido.
    private func updateWaveformForExpansion() {
        let onMediaPage = isExpanded && currentDroplet == .media
        waveformStopTask?.cancel()
        waveformStopTask = nil
        if onMediaPage {
            guard config.liveWaveform, media.nowPlaying.isPlaying, let wf = waveform else { return }
            wf.start()
        } else {
            waveformStopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.waveform?.stop()
            }
        }
    }

    /// Liga o polling do `playerBridge` só quando a ilha está expandida na
    /// página de mídia E o Music.app ou o Spotify está rodando; desliga no resto.
    private func updatePlayerBridgePolling() {
        let onMediaPage = isExpanded && currentDroplet == .media
        let playerRunning = onMediaPage && (
            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
            || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
        )
        if playerRunning {
            playerBridge.startPolling()
        } else {
            playerBridge.stopPolling()
        }
    }
    /// Retângulo da ilha (colapsada ou expandida) no espaço `.global` do
    /// SwiftUI hospedado — mesma origem top-left/y-down do host view do painel.
    /// `DropHostView` usa pra só aceitar drop dentro da ilha, nunca do painel
    /// transparente inteiro (I3).
    /// Frame da ilha POR TELA (coords do hosting view de cada painel). Um só valor
    /// pra todas era a raiz do loop/corte: as duas views se sobrescreviam.
    @Published var islandFrames: [CGDirectDisplayID: CGRect] = [:]
    var islandFrame: CGRect { islandFrames.values.max(by: { $0.height < $1.height }) ?? .zero }

    func updateConfig(_ mutate: (inout NotchConfig) -> Void) {
        let wasSuppressing = config.suppressSystemHUD
        let previousRingHotKey = config.ringHotKey
        let previousDropletHotKeys = config.dropletHotKeys
        let wasShowingVPNHUD = config.showVPNHUD
        let previousClipboardLimit = config.clipboardLimit
        let previousClipboardRetentionDays = config.clipboardRetentionDays
        let previousCalendarIDs = config.calendarIDs
        let previousHighAlertDuration = config.highAlertDuration
        let previousOnboardingDone = config.onboardingDone
        let wasShowingWeather = config.showWeather
        mutate(&config)
        NotchConfigStore.save(config)
        if config.onboardingDone, !previousOnboardingDone, AppEnvironment.isBundledApp {
            startBluetooth()
        }
        if config.showWeather != wasShowingWeather {
            if config.showWeather { weather.start() } else { weather.stop() }
        }
        if config.highAlertDuration != previousHighAlertDuration {
            highAlert.lastDuration = HighAlert.Duration(rawValue: config.highAlertDuration) ?? .infinite
        }
        if config.clipboardLimit != previousClipboardLimit || config.clipboardRetentionDays != previousClipboardRetentionDays {
            clipboard.updatePolicy(limit: config.clipboardLimit, retentionDays: config.clipboardRetentionDays)
        }
        if config.calendarIDs != previousCalendarIDs {
            calendar.selectedCalendarIDs = config.calendarIDs
        }
        if config.ringHotKey != previousRingHotKey {
            registerRingHotKey(notifyOnFailure: true)
        }
        if config.dropletHotKeys != previousDropletHotKeys {
            for d in Droplet.allCases where config.dropletHotKeys[d.rawValue] != previousDropletHotKeys[d.rawValue] {
                registerDropletHotKey(d, notifyOnFailure: true)
            }
        }
        if wasShowingVPNHUD != config.showVPNHUD {
            updateAmbientActivity(timerSession: timers.session)
        }
        if config.suppressSystemHUD {
            hudSuppressor.enable()
            keyTap.start(prompt: !wasSuppressing)  // prompt só se o usuário acabou de ligar
        } else {
            hudSuppressor.disable()
            keyTap.stop()
        }
        brightness.setSlowMode(keyTap.active)
        if !config.liveWaveform { waveform?.stop() }
        // showCalendar/showVPNHUD podem ligar/desligar sem passar por
        // updateAmbientActivity (que já roda no branch de VPN acima) — reavalia
        // sempre, é barato e idempotente (#33).
        updateAmbientTickScheduling()
    }

    func shutdown() {
        ambientTick?.invalidate()
        hudSuppressor.disable()
        hotKeyCenter.unregisterAll()
        showActions = false
        cancelActivityExpandedDismiss()
        showActivityExpanded = false
        captureTask?.cancel()
        ScreenCapture.cancelIfRunning()
        TerminalSession.shared.terminate()
        voice.stopSync()
        screenRecorder.stopSync()
        if config.clearClipboardOnQuit { clipboard.clear() }
    }
}

/// Pedido da UI com sequência única: dois pedidos iguais seguidos ainda disparam
/// `onChange` (o SwiftUI não enxerga o `nil` intermediário setado dentro do handler).
/// `displayID`: tela alvo, carimbada por quem pediu (hotkey/ring/jiggle/drop
/// miram a tela sob o mouse; `nil` mira a ilha PRIMÁRIA — a do notch real, ou
/// a primeira tela com painel se nenhuma tiver notch) (#30).
struct UIRequest<Value: Equatable>: Equatable {
    let seq: Int
    let value: Value
    var displayID: CGDirectDisplayID?

    /// Pura: este pedido é pra ESTA tela? `own` é o `displayID` do
    /// `NotchView` que está perguntando, `primary` diz se ele é a ilha primária.
    func targets(displayID own: CGDirectDisplayID, primary: Bool) -> Bool {
        guard let displayID else { return primary }
        return displayID == own
    }
}
