import AppKit
import Combine
import CoreGraphics
import Foundation

/// Foco (DND), lock/unlock de tela e chime de hora — eventos leves da ilha.
@MainActor
final class SystemEvents: ObservableObject {
    var onFocusChange: ((Bool) -> Void)?
    /// Evento de bloqueio/desbloqueio (peek "Bloqueado" + som) — só dispara
    /// pelas notificações distribuídas, nunca pela re-derivação no wake.
    var onScreenLock: ((Bool) -> Void)?
    var onHourlyChime: (() -> Void)?

    /// Tela bloqueada AGORA. `com.apple.screenIsLocked` só vira `true` depois
    /// de CONFIRMADO pelo servidor de sessão (`CGSessionCopyCurrentDictionary`
    /// — a notificação distribuída é postável por qualquer processo do usuário
    /// e decidiria sozinha mandar a ilha pro space do loginwindow, mouse
    /// ignorado, acima de tudo). Unlock é fail-closed (só some do lock) e o
    /// wake re-deriva da mesma fonte (o app pode estar suspenso no lock).
    @Published private(set) var isScreenLocked: Bool = SystemEvents.isScreenActuallyLocked()
    /// Foco (DND) ativo AGORA — escrito pelo mesmo poll de 5 s do `onFocusChange`
    /// (widget "Foco" da tela de bloqueio; sem timer novo).
    @Published private(set) var isFocusActive = false

    private var focusTimer: Timer?
    private var chimeTimer: Timer?
    private var lastFocus: Bool?

    private var assertionsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    }

    init() {
        // lock/unlock via distributed notifications
        let dnc = DistributedNotificationCenter.default()
        // `isScreenLocked` ANTES do callback: quem observa o estado colapsa a
        // ilha (e limpa o trailing); o peek "Bloqueado" nasce depois, intacto.
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) {
            [weak self] _ in Task { @MainActor in await self?.confirmAndPublishLock() }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) {
            [weak self] _ in Task { @MainActor in self?.setLocked(false); self?.onScreenLock?(false) }
        }
        // wake (sistema/tela) e fim do protetor: o lock pode ter acontecido com o
        // processo suspenso (tampa fechada) — re-deriva da fonte autoritativa.
        let wsnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            wsnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.rederiveLock() }
            }
        }
        dnc.addObserver(forName: .init("com.apple.screensaver.didstop"), object: nil, queue: .main) {
            [weak self] _ in Task { @MainActor in self?.rederiveLock() }
        }
        // foco: poll do arquivo de assertions do DND (não tem API pública de leitura)
        isFocusActive = focusActive
        focusTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkFocus() }
        }
        // chime de hora
        scheduleChime()
    }

    private func setLocked(_ locked: Bool) {
        if isScreenLocked != locked { isScreenLocked = locked }
    }

    /// Só publica o lock que a sessão confirma. O flag CGS pode chegar alguns
    /// ms depois da notificação real → re-check em 500 ms (descartar direto
    /// sumiria com a ilha de um lock verdadeiro até o próximo wake). Spoof
    /// (notificação sem lock real): nada — nem estado, nem peek, nem som.
    private func confirmAndPublishLock() async {
        if Self.isScreenActuallyLocked() {
            setLocked(true); onScreenLock?(true)
            return
        }
        try? await Task.sleep(for: .milliseconds(500))
        // `!isScreenLocked`: se outra notificação confirmou no meio-tempo, não
        // repete o peek/som.
        guard Self.isScreenActuallyLocked(), !isScreenLocked else { return }
        setLocked(true); onScreenLock?(true)
    }

    private func rederiveLock() {
        setLocked(Self.isScreenActuallyLocked())
    }

    /// Verdade do servidor de sessão do CoreGraphics (não é notificação
    /// spoofável). Sem dicionário → "não bloqueada".
    nonisolated static func isScreenActuallyLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    var focusActive: Bool {
        guard let data = try? Data(contentsOf: assertionsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = (obj["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]]
        else { return false }
        return !records.isEmpty
    }

    private func checkFocus() {
        let now = focusActive
        if isFocusActive != now { isFocusActive = now }
        if let last = lastFocus, last != now {
            onFocusChange?(now)
        }
        lastFocus = now
    }

    private func scheduleChime() {
        let cal = Calendar.current
        let nextHour = cal.nextDate(after: Date(), matching: DateComponents(minute: 0, second: 0),
                                    matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        chimeTimer = Timer(fire: nextHour, interval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onHourlyChime?() }
        }
        RunLoop.main.add(chimeTimer!, forMode: .common)
    }

    private static var cache: [String: NSSound] = [:]

    /// Sons próprios (Resources/Sounds/*.wav, sintetizados por make-sounds.py);
    /// sem o arquivo, cai no som de sistema com o mesmo nome.
    static func playSound(_ name: String) {
        if let s = cache[name] { s.stop(); s.play(); return }
        if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"),
           let s = NSSound(contentsOf: url, byReference: true) {
            cache[name] = s
            s.play()
        } else {
            NSSound(named: name)?.play()
        }
    }
}
