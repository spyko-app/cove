import Foundation

enum ActivityAction: Equatable {
    case timerToggle
    case timerStop
    case timerExtend(Int)
    case highAlertToggle
    case highAlertStop
    case joinMeeting(URL)
    case openCalendar
    case snoozeEvent(Int)
    case replyNotification
    case openNotifications
    case switchOutput
    case openBatterySettings
    case stopRecording
    case stopScreenRecording
}

struct QuickAction: Equatable, Identifiable {
    let id: String
    let title: String
    let symbol: String
    let action: ActivityAction
}

enum ActivityExpansion {
    static let batterySettingsURL = "x-apple.systempreferences:com.apple.Battery-Settings.extension"

    struct Regions: Equatable {
        var symbol: String
        var tint: Tint
        var title: String
        var subtitle: String
        var value: String?
        var actions: [QuickAction]
    }

    enum Tint: String, Equatable {
        case white, red, orange, yellow, green, purple, gray
    }

    struct Context: Equatable {
        var now = Date()
        var timerRunning = true
        var recordingFailed = false

        init(now: Date = Date(), timerRunning: Bool = true, recordingFailed: Bool = false) {
            self.now = now
            self.timerRunning = timerRunning
            self.recordingFailed = recordingFailed
        }
    }

    static func isAlerting(_ a: NotchActivity, context: Context = Context()) -> Bool {
        switch a {
        case .battery(let s): return !s.onAC && s.percent <= 10
        case .eventCountdown(_, let start, _):
            let delta = start.timeIntervalSince(context.now)
            return delta <= 60 && delta >= 0
        case .vpn(let up): return !up
        case .recording, .screenRecording: return context.recordingFailed
        default: return false
        }
    }

    static func actions(for a: NotchActivity, context: Context = Context()) -> [QuickAction] {
        switch a {
        case .timer:
            return [
                context.timerRunning
                    ? QuickAction(id: "timer.pause", title: "Pausar", symbol: "pause.fill", action: .timerToggle)
                    : QuickAction(id: "timer.resume", title: "Retomar", symbol: "play.fill", action: .timerToggle),
                QuickAction(id: "timer.stop", title: "Parar", symbol: "stop.fill", action: .timerStop),
                QuickAction(id: "timer.plus5", title: "+5 min", symbol: "plus", action: .timerExtend(5 * 60)),
            ]
        case .highAlert:
            return [QuickAction(id: "alert.stop", title: "Desligar", symbol: "stop.fill", action: .highAlertStop)]
        case .event:
            return [
                QuickAction(id: "event.calendar", title: "Abrir no Calendário", symbol: "calendar", action: .openCalendar),
                QuickAction(id: "event.snooze", title: "Adiar 5 min", symbol: "clock.arrow.circlepath", action: .snoozeEvent(5 * 60)),
            ]
        case .eventCountdown(_, _, let url):
            let first = url.map {
                QuickAction(id: "event.join", title: "Entrar", symbol: "video.fill", action: .joinMeeting($0))
            } ?? QuickAction(id: "event.calendar", title: "Abrir no Calendário", symbol: "calendar", action: .openCalendar)
            return [
                first,
                QuickAction(id: "event.snooze", title: "Adiar 5 min", symbol: "clock.arrow.circlepath", action: .snoozeEvent(5 * 60)),
            ]
        case .notification:
            return [
                QuickAction(id: "note.reply", title: "Responder", symbol: "arrowshape.turn.up.left.fill", action: .replyNotification),
                QuickAction(id: "note.open", title: "Abrir", symbol: "bell.badge.fill", action: .openNotifications),
            ]
        case .device(_, let connected, _):
            guard connected else { return [] }
            return [QuickAction(id: "device.output", title: "Trocar saída", symbol: "airpodspro", action: .switchOutput)]
        case .battery, .lowPowerMode:
            return [QuickAction(id: "battery.settings", title: "Abrir Bateria", symbol: "battery.100percent", action: .openBatterySettings)]
        case .recording:
            return [QuickAction(id: "rec.stop", title: "Parar", symbol: "stop.fill", action: .stopRecording)]
        case .screenRecording:
            return [QuickAction(id: "screenrec.stop", title: "Parar", symbol: "stop.fill", action: .stopScreenRecording)]
        default:
            return []
        }
    }

    static func regions(for a: NotchActivity, context: Context = Context()) -> Regions {
        let acts = actions(for: a, context: context)
        switch a {
        case .volume(let v, let muted):
            return Regions(symbol: muted ? "speaker.slash.fill" : "speaker.fill", tint: .white,
                           title: muted ? "Mudo" : "Som", subtitle: "Volume do sistema",
                           value: "\(Int((v * 100).rounded()))", actions: acts)
        case .brightness(let v):
            return Regions(symbol: "sun.max.fill", tint: .white, title: "Brilho", subtitle: "Tela principal",
                           value: "\(Int((v * 100).rounded()))", actions: acts)
        case .keyboardBrightness(let v):
            return Regions(symbol: "keyboard", tint: .white, title: "Teclado", subtitle: "Iluminação",
                           value: "\(Int((v * 100).rounded()))", actions: acts)
        case .battery(let s):
            let tint: Tint = s.onAC ? .green : (s.percent <= 20 ? .red : .white)
            return Regions(symbol: s.onAC ? "battery.100percent.bolt" : "battery.25percent", tint: tint,
                           title: "Bateria", subtitle: s.onAC ? "Na tomada" : "Sem tomada",
                           value: "\(s.percent)%", actions: acts)
        case .lowPowerMode(let on):
            return Regions(symbol: "leaf.fill", tint: on ? .yellow : .gray,
                           title: on ? "Economia de energia" : "Consumo normal", subtitle: "Bateria",
                           value: nil, actions: acts)
        case .device(let name, let connected, let battery):
            return Regions(symbol: DeviceSymbol.symbol(for: name, connected: connected), tint: connected ? .white : .gray,
                           title: name, subtitle: connected ? "Conectado" : "Desconectado",
                           value: battery.map { "\($0)%" }, actions: acts)
        case .focus(let on):
            return Regions(symbol: on ? "moon.fill" : "moon", tint: on ? .purple : .gray,
                           title: on ? "Foco ativado" : "Foco desativado", subtitle: "Não perturbe",
                           value: nil, actions: acts)
        case .lock(let locked):
            return Regions(symbol: locked ? "lock.fill" : "lock.open.fill", tint: .white,
                           title: locked ? "Bloqueado" : "Desbloqueado", subtitle: "Tela", value: nil, actions: acts)
        case .event(let title, let minutes):
            return Regions(symbol: "calendar", tint: .red, title: title,
                           subtitle: minutes > 0 ? "Começa em \(minutes) min" : "Agora",
                           value: minutes > 0 ? "\(minutes)m" : nil, actions: acts)
        case .eventCountdown(let title, let start, _):
            let mins = Int((start.timeIntervalSince(context.now) / 60).rounded(.up))
            return Regions(symbol: "calendar", tint: .red, title: title,
                           subtitle: mins > 0 ? "em \(mins) min" : "agora",
                           value: mins > 0 ? "\(mins)m" : "agora", actions: acts)
        case .notification(let app, let title):
            return Regions(symbol: "bell.badge.fill", tint: .orange, title: title, subtitle: app,
                           value: nil, actions: acts)
        case .track(let title, let artist):
            return Regions(symbol: "music.note", tint: .white, title: title, subtitle: artist,
                           value: nil, actions: acts)
        case .timer(let label, let remaining):
            return Regions(symbol: "timer", tint: .white, title: label,
                           subtitle: context.timerRunning ? "Em andamento" : "Pausado",
                           value: mmss(remaining), actions: acts)
        case .recording(let elapsed):
            return Regions(symbol: "mic.fill", tint: .red, title: "Gravando",
                           subtitle: context.recordingFailed ? "Parou com erro" : "Memo de voz",
                           value: mmss(elapsed), actions: acts)
        case .screenRecording(let elapsed):
            return Regions(symbol: "record.circle.fill", tint: .red, title: "Gravando tela",
                           subtitle: context.recordingFailed ? "Parou com erro" : "Tela inteira",
                           value: mmss(elapsed), actions: acts)
        case .wifi(let ssid, let connected):
            return Regions(symbol: connected ? "wifi" : "wifi.slash", tint: connected ? .white : .gray,
                           title: connected ? (ssid ?? "Wi-Fi conectado") : "Wi-Fi desligado",
                           subtitle: "Rede", value: nil, actions: acts)
        case .hotspot(let on):
            return Regions(symbol: "personalhotspot", tint: on ? .white : .gray,
                           title: on ? "Hotspot ligado" : "Hotspot desligado", subtitle: "Rede",
                           value: nil, actions: acts)
        case .drive(let name, let mounted):
            return Regions(symbol: mounted ? "externaldrive.fill" : "externaldrive.badge.minus", tint: .white,
                           title: name, subtitle: mounted ? "Montado" : "Ejetado", value: nil, actions: acts)
        case .vpn(let up):
            return Regions(symbol: up ? "lock.shield.fill" : "lock.open", tint: up ? .white : .gray,
                           title: up ? "VPN conectada" : "VPN desconectada", subtitle: "Rede",
                           value: nil, actions: acts)
        case .vpnSession(let since):
            return Regions(symbol: "lock.shield.fill", tint: .white, title: "VPN conectada",
                           subtitle: "Sessão em andamento",
                           value: mmss(Int(context.now.timeIntervalSince(since))), actions: acts)
        case .highAlert(let expiresAt):
            let left = Int(expiresAt.timeIntervalSince(context.now))
            return Regions(symbol: "bolt.fill", tint: .yellow, title: "High Alert",
                           subtitle: "Mac acordado", value: mmss(max(0, left)), actions: acts)
        }
    }

    static func mmss(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
