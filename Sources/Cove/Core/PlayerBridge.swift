import AppKit
import Foundation
import ScriptingBridge

/// Modo de repetição, mapeado do enum nativo do player. Spotify só expõe um
/// booleano (`repeating`) — sem distinguir "uma faixa" de "tudo" — então lá
/// vira sempre `.off`/`.all`; `.one` só é alcançável via Music.app.
enum RepeatMode: Equatable {
    case off, all, one
}

/// Estado de shuffle/repeat/favorito do player ativo — struct pura, sem IO,
/// só o suficiente pra UI decidir símbolo/tint (`symbol(for:)`, testável sem
/// ScriptingBridge nem player nenhum rodando).
struct PlayerState: Equatable {
    var shuffle = false
    var repeatMode: RepeatMode = .off
    /// nil = player não expõe favorito (Spotify); Bool = estado real (Music).
    var favorite: Bool?
    var supportsFavorite = false

    /// Um controle do card de mídia — puro, testável sem ScriptingBridge.
    enum Control: Equatable {
        case shuffle(Bool)
        case repeatMode(RepeatMode)
        case favorite(Bool?)
    }

    /// Mapeamento estado→símbolo SF Symbols + se deve aparecer "tintado" (ativo).
    /// shuffle→"shuffle" (tintado se ligado) · repeat off→"repeat" apagado ·
    /// all→"repeat" tintado · one→"repeat.1" tintado · favorito→"heart"/"heart.fill".
    static func symbol(for control: Control) -> (name: String, tinted: Bool) {
        switch control {
        case .shuffle(let on):
            return ("shuffle", on)
        case .repeatMode(let mode):
            switch mode {
            case .off: return ("repeat", false)
            case .all: return ("repeat", true)
            case .one: return ("repeat.1", true)
            }
        case .favorite(let on):
            return (on == true ? "heart.fill" : "heart", on == true)
        }
    }
}

/// Os dois players suportados via ScriptingBridge — "Fila" (Playing Next) não
/// entra, nenhum dos dois expõe API pra isso.
enum Player: Equatable, CaseIterable {
    case music, spotify

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }
}

/// Controla shuffle/repeat/favorito do Music.app/Spotify via ScriptingBridge
/// dinâmico (KVC sobre `SBApplication`/`SBObject` — sem header gerado, só
/// nomes de propriedade documentados nos respectivos `.sdef`). A 1ª chamada
/// dispara o TCC de Automation (texto em `NSAppleEventsUsageDescription`,
/// Info.plist + `scripts/make-app.sh`).
///
/// Polling de 2s ligado/desligado por `NotchCoordinator.updatePlayerBridgePolling()`
/// — só enquanto a ilha está expandida na página de mídia E algum dos dois
/// players está rodando. A construção da classe em si não toca ScriptingBridge
/// (nada de `SBApplication` no `init`) — só `refresh()`/`toggle*()` tocam, e só
/// disparam quando o player alvo está `isRunning` (nunca auto-lança o app).
@MainActor
final class PlayerBridge: ObservableObject {
    @Published private(set) var state = PlayerState()
    @Published private(set) var isAvailable = false

    /// Título da faixa exibida no card (`MediaRemoteService.nowPlaying.title`),
    /// injetado pelo `NotchCoordinator` — usado pra desempatar Music×Spotify
    /// quando os dois estão rodando. Chamado a cada tick do polling.
    var nowPlayingTitleProvider: (() -> String?)?

    private var timer: Timer?
    private var detected: Player?
    private var terminationObservers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        let bundleIDs = Set(Player.allCases.map(\.bundleID))
        terminationObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier,
                  bundleIDs.contains(id) else { return }
            Task { @MainActor in self?.handleAppLifecycleChange() }
        })
        terminationObservers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier,
                  bundleIDs.contains(id) else { return }
            Task { @MainActor in self?.handleAppLifecycleChange() }
        })
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in terminationObservers { center.removeObserver(observer) }
    }

    /// O player ativo terminou (ou um novo apareceu) — reavalia sem esperar o
    /// próximo tick do timer. Se nenhum player suportado mais roda, para o
    /// polling e limpa o estado (nada fica "preso" no último player fechado).
    private func handleAppLifecycleChange() {
        guard timer != nil else { refresh(); return }
        if runningPlayers().isEmpty {
            stopPolling()
            detected = nil
            isAvailable = false
            state = PlayerState()
        } else {
            refresh(nowPlayingTitle: nowPlayingTitleProvider?())
        }
    }

    func startPolling() {
        guard timer == nil else { return }
        refresh(nowPlayingTitle: nowPlayingTitleProvider?())
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(nowPlayingTitle: self?.nowPlayingTitleProvider?()) }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func runningPlayers() -> [Player] {
        Player.allCases.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
    }

    private func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    private func app(for player: Player) -> SBApplication? {
        guard isRunning(player) else { return nil }
        return SBApplication(bundleIdentifier: player.bundleID)
    }

    private func currentTrack(_ app: SBApplication) -> SBObject? {
        app.value(forKey: "currentTrack") as? SBObject
    }

    private func trackName(for player: Player) -> String? {
        guard let app = app(for: player), let track = currentTrack(app) else { return nil }
        return track.value(forKey: "name") as? String
    }

    private func isPlaying(_ player: Player) -> Bool {
        guard let app = app(for: player), let raw = app.value(forKey: "playerState") as? NSNumber else { return false }
        // KVC `playerState` (Music/Spotify expõem os dois; enum `kPSP` = "playing" no .sdef).
        let playing: UInt32 = 0x6B50_5350
        return raw.uint32Value == playing
    }

    /// Escolha pura, sem IO: recebe o que já foi lido (players rodando, título
    /// atual do card, título e estado playing de cada um) e devolve qual
    /// controlar. Ordem: título bate com a faixa atual do card → vence; senão
    /// o que está tocando (`playerState` == playing) → vence; senão Music
    /// (fallback estável quando nada desempata, ex.: os dois pausados).
    nonisolated static func choosePlayer(
        running: [Player],
        nowPlayingTitle: String?,
        titles: [Player: String?],
        playing: [Player: Bool]
    ) -> Player? {
        guard !running.isEmpty else { return nil }
        guard running.count > 1 else { return running.first }
        if let title = nowPlayingTitle, !title.isEmpty {
            if let match = running.first(where: { (titles[$0] ?? nil) == title }) { return match }
        }
        if let match = running.first(where: { playing[$0] == true }) { return match }
        return running.contains(.music) ? .music : running.first
    }

    private func detectPlayer(preferredTitle: String?) -> Player? {
        let running = runningPlayers()
        guard running.count > 1 else { return running.first }
        var titles: [Player: String?] = [:]
        var playing: [Player: Bool] = [:]
        for player in running {
            titles[player] = trackName(for: player)
            playing[player] = isPlaying(player)
        }
        return Self.choosePlayer(running: running, nowPlayingTitle: preferredTitle, titles: titles, playing: playing)
    }

    /// Lê o estado atual do player detectado — chamado a cada tick do timer
    /// (e uma vez na hora de ligar o polling). `nowPlayingTitle` vem do
    /// `MediaRemoteService` já exibido no card, pra desempatar Music×Spotify.
    func refresh(nowPlayingTitle: String? = nil) {
        guard let player = detectPlayer(preferredTitle: nowPlayingTitle), let app = app(for: player) else {
            isAvailable = false
            detected = nil
            state = PlayerState()
            return
        }
        detected = player
        isAvailable = true
        switch player {
        case .music:
            let shuffle = (app.value(forKey: "shuffleEnabled") as? Bool) ?? false
            let repeatMode = Self.musicRepeatMode(from: app.value(forKey: "songRepeat"))
            var favorite: Bool?
            if let track = currentTrack(app) {
                if let f = track.value(forKey: "favorited") as? Bool { favorite = f }
                else if let l = track.value(forKey: "loved") as? Bool { favorite = l }
            }
            state = PlayerState(shuffle: shuffle, repeatMode: repeatMode, favorite: favorite, supportsFavorite: favorite != nil)
        case .spotify:
            let shuffle = (app.value(forKey: "shuffling") as? Bool) ?? false
            let repeating = (app.value(forKey: "repeating") as? Bool) ?? false
            // sem "one" na API do Spotify — nunca oferecer symbol .one aqui.
            state = PlayerState(shuffle: shuffle, repeatMode: repeating ? .all : .off, favorite: nil, supportsFavorite: false)
        }
    }

    func toggleShuffle() {
        guard let player = detected, let app = app(for: player) else { return }
        switch player {
        case .music: app.setValue(!state.shuffle, forKey: "shuffleEnabled")
        case .spotify: app.setValue(!state.shuffle, forKey: "shuffling")
        }
        refresh(nowPlayingTitle: nowPlayingTitleProvider?())
    }

    func cycleRepeat() {
        guard let player = detected, let app = app(for: player) else { return }
        switch player {
        case .music:
            let next: RepeatMode
            switch state.repeatMode {
            case .off: next = .all
            case .all: next = .one
            case .one: next = .off
            }
            app.setValue(Self.musicRepeatRaw(for: next), forKey: "songRepeat")
        case .spotify:
            app.setValue(!(state.repeatMode == .all), forKey: "repeating")
        }
        refresh(nowPlayingTitle: nowPlayingTitleProvider?())
    }

    func toggleFavorite() {
        guard state.supportsFavorite, let player = detected, player == .music,
              let app = app(for: player), let track = currentTrack(app) else { return }
        let newValue = !(state.favorite ?? false)
        if track.value(forKey: "favorited") != nil {
            track.setValue(newValue, forKey: "favorited")
        } else {
            track.setValue(newValue, forKey: "loved")
        }
        refresh(nowPlayingTitle: nowPlayingTitleProvider?())
    }

    // Enum `song repeat` do Music.sdef (MusicERpt): off='kRpO' one='kRp1' all='kAll'.
    // Sem header gerado (regra do ciclo) — ScriptingBridge entrega o FourCharCode
    // cru via KVC; comparado aqui contra as constantes públicas do próprio .sdef.
    private static let musicRptOff: UInt32 = 0x6B52_704F
    private static let musicRptOne: UInt32 = 0x6B52_7031
    private static let musicRptAll: UInt32 = 0x6B41_6C6C

    private static func musicRepeatMode(from raw: Any?) -> RepeatMode {
        let code: UInt32?
        if let n = raw as? NSNumber { code = n.uint32Value } else { code = nil }
        switch code {
        case musicRptOne: return .one
        case musicRptAll: return .all
        default: return .off
        }
    }

    private static func musicRepeatRaw(for mode: RepeatMode) -> UInt32 {
        switch mode {
        case .off: return musicRptOff
        case .all: return musicRptAll
        case .one: return musicRptOne
        }
    }
}
