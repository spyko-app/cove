import Foundation

/// Fila pura de `NotchActivity` — sem estado externo, sem `Date()` implícito.
/// Lição #6 do changelog do Droppy: HUD substitui na hora; evento enfileira
/// atrás do que já está na tela; mesmo tipo de evento coalesce (o mais novo
/// substitui o payload mantendo a posição); item enfileirado expira se
/// esperou mais que a própria duração × 2 (descarta, não mostra velho).
struct ActivityQueue {
    struct Entry {
        let activity: NotchActivity
        let duration: Double
        let enqueuedAt: Date
    }

    /// O que fazer com uma atividade recém-chegada, dado o que está na tela agora.
    enum Decision: Equatable {
        case showNow
        case enqueue
    }

    private(set) var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }

    /// HUD sempre mostra na hora; evento sobre HUD ou sobre nada também mostra
    /// na hora; evento igual ao que já está na tela reinicia no lugar (mesmo
    /// slot); só evento DIFERENTE sobre evento na tela espera a vez.
    func decision(for a: NotchActivity, current: NotchActivity?) -> Decision {
        if a.isHUD { return .showNow }
        guard let current else { return .showNow }
        if current.isHUD { return .showNow }
        if current == a { return .showNow }
        return .enqueue
    }

    /// Enfileira coalescendo por `kindKey`: se já existe uma entrada do mesmo
    /// tipo, substitui o payload/duração mantendo a posição original na fila.
    mutating func enqueue(_ a: NotchActivity, duration: Double, now: Date) {
        let key = a.kindKey
        if let idx = entries.firstIndex(where: { $0.activity.kindKey == key }) {
            entries[idx] = Entry(activity: a, duration: duration, enqueuedAt: now)
        } else {
            entries.append(Entry(activity: a, duration: duration, enqueuedAt: now))
        }
    }

    /// Remove da fila todo item de um tipo (ex.: notificação enfileirada no
    /// instante em que a tela bloqueia — nunca pode sair depois, no lock).
    mutating func removeAll(kindKey: String) {
        entries.removeAll { $0.activity.kindKey == kindKey }
    }

    /// Tira o próximo da fila (FIFO), descartando silenciosamente qualquer
    /// item na frente que já expirou (esperou mais que `duration * 2`).
    mutating func next(now: Date) -> Entry? {
        while !entries.isEmpty {
            let candidate = entries.removeFirst()
            if now.timeIntervalSince(candidate.enqueuedAt) > candidate.duration * 2 {
                continue
            }
            return candidate
        }
        return nil
    }
}

extension NotchActivity {
    /// Identidade do "tipo" da atividade sem payload — usada pra coalescing
    /// na fila (duas notificações seguidas do mesmo tipo colapsam em uma).
    var kindKey: String {
        switch self {
        case .volume: "volume"
        case .brightness: "brightness"
        case .battery: "battery"
        case .lowPowerMode: "lowPowerMode"
        case .device: "device"
        case .focus: "focus"
        case .lock: "lock"
        case .event: "event"
        case .eventCountdown: "eventCountdown"
        case .notification: "notification"
        case .track: "track"
        case .keyboardBrightness: "keyboardBrightness"
        case .timer: "timer"
        case .recording: "recording"
        case .screenRecording: "screenRecording"
        case .wifi: "wifi"
        case .hotspot: "hotspot"
        case .drive: "drive"
        case .vpn: "vpn"
        case .vpnSession: "vpnSession"
        case .highAlert: "highAlert"
        }
    }
}

extension NotchActivity {
    /// Versão SEGURA pra tela de bloqueio: todo texto livre (título de evento,
    /// rótulo de timer, nome de disco/dispositivo, SSID, corpo/remetente de
    /// notificação) vira genérico — o macOS não mostra prévia nenhuma no
    /// lock, a ilha também não. Mantém o payload não-textual (start, URL,
    /// bateria, estado) pra ring/valor continuarem certos. Pura: aplicada na
    /// renderização (`NotchView`) enquanto `isScreenLocked`.
    var redactedForLockScreen: NotchActivity {
        switch self {
        case .event(_, let minutes):
            .event(title: "Evento", minutes: minutes)
        case .eventCountdown(_, let start, let meetingURL):
            .eventCountdown(title: "Evento", start: start, meetingURL: meetingURL)
        case .timer(_, let remaining):
            .timer(label: "", remaining: remaining)
        case .drive(_, let mounted):
            .drive(name: "Disco", mounted: mounted)
        case .device(_, let connected, let battery):
            .device(name: "Dispositivo", connected: connected, battery: battery)
        case .wifi(_, let connected):
            .wifi(ssid: nil, connected: connected)
        case .notification(let app, _):
            .notification(app: app, title: "")
        default:
            self
        }
    }
}
