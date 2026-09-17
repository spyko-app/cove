import Foundation

/// Widgets da tela de bloqueio (estilo Alcove): linha de "ícone + texto"
/// embaixo do relógio do macOS. Modelo PURO — quem lê os serviços é o
/// `LockWidgetsController`; aqui só a regra de quais aparecem e com que texto.
enum LockScreenWidget: String, Codable, CaseIterable {
    case focus, weather, battery, media, calendar, timer

    /// Rótulo do toggle em Ajustes › Telas.
    var label: String {
        switch self {
        case .focus: "Foco"
        case .weather: "Clima"
        case .battery: "Bateria"
        case .media: "Mídia tocando"
        case .calendar: "Próximo evento"
        case .timer: "Timer"
        }
    }

    static let defaults: [LockScreenWidget] = [.focus, .weather, .battery, .media]

    /// Decode tolerante: valor desconhecido no JSON é ignorado (nunca derruba
    /// o config inteiro — precedente `wideIsland`). `nil` (chave ausente) → padrão.
    static func decode(_ raw: [String]?) -> [LockScreenWidget] {
        guard let raw else { return defaults }
        return raw.compactMap(LockScreenWidget.init(rawValue:))
    }
}

/// Um widget resolvido: símbolo SF + texto curto. `id` = tipo (um por tipo).
struct LockScreenWidgetItem: Equatable, Identifiable {
    let kind: LockScreenWidget
    let symbol: String
    let text: String
    var id: LockScreenWidget { kind }
}

/// Regra pura: devolve só os widgets HABILITADOS e COM DADO, na ordem
/// canônica de `LockScreenWidget.allCases` (o array da config é só o conjunto
/// ligado — a ordem nos Ajustes não é editável).
enum LockScreenWidgetsModel {
    /// Janela em que o próximo evento aparece (mesma do `CalendarService.next`).
    static let eventWindow: TimeInterval = 12 * 3600

    static func items(config: [LockScreenWidget],
                      focusActive: Bool,
                      weather: WeatherService.Weather?,
                      battery: PowerService.BatteryState?,
                      media: NowPlaying?,
                      nextEvent: CalendarService.UpcomingEvent?,
                      timer: TimerService.Session?,
                      now: Date = Date(),
                      timeZone: TimeZone = .current,
                      locale: Locale = .current) -> [LockScreenWidgetItem] {
        let enabled = Set(config)
        var out: [LockScreenWidgetItem] = []
        for kind in LockScreenWidget.allCases where enabled.contains(kind) {
            switch kind {
            case .focus:
                // o NOME do modo exige API privada — só "Foco" quando ativo
                if focusActive { out.append(.init(kind: kind, symbol: "moon.fill", text: "Foco")) }
            case .weather:
                if let w = weather {
                    out.append(.init(kind: kind, symbol: w.symbol, text: "\(Int(w.tempC.rounded()))°"))
                }
            case .battery:
                if let b = battery {
                    out.append(.init(kind: kind, symbol: batterySymbol(percent: b.percent, plugged: b.onAC || b.charging),
                                     text: "\(b.percent)%"))
                }
            case .media:
                // só tocando; pausado some (a ilha também recolhe as asas)
                if let m = media, m.isPlaying, !m.title.isEmpty {
                    let text = m.artist.isEmpty ? m.title : "\(m.title) · \(m.artist)"
                    out.append(.init(kind: kind, symbol: "music.note", text: text))
                }
            case .calendar:
                // título GENÉRICO por privacidade (mesma regra do `redactedForLockScreen`)
                if let e = nextEvent, let t = eventText(start: e.start, now: now, timeZone: timeZone, locale: locale) {
                    out.append(.init(kind: kind, symbol: "calendar", text: t))
                }
            case .timer:
                // só CORRENDO: pausado some (a ilha faz igual — `updateAmbientActivity`);
                // contagem parada ao lado do relógio pareceria um timer vivo
                if let s = timer, s.isRunning {
                    out.append(.init(kind: kind, symbol: "timer", text: timerText(remaining: s.remaining)))
                }
            }
        }
        return out
    }

    /// Família `…percent` (a mesma do `PeekIcon`); raio quando plugado —
    /// a 100 % na tomada `charging` é false, mas o Mac está na tomada.
    static func batterySymbol(percent: Int, plugged: Bool) -> String {
        if plugged { return "battery.100percent.bolt" }
        switch percent {
        case 90...: return "battery.100percent"
        case 60..<90: return "battery.75percent"
        case 35..<60: return "battery.50percent"
        case 10..<35: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// "Evento 15:00" só pra evento FUTURO dentro de 12 h; `nil` fora disso
    /// (o `next` do serviço pode estar stale até o refresh de 60 s). Hora no
    /// formato do locale (12/24 h como o relógio do lock e o resto do app).
    static func eventText(start: Date, now: Date, timeZone: TimeZone = .current,
                          locale: Locale = .current) -> String? {
        let delta = start.timeIntervalSince(now)
        guard delta > 0, delta <= eventWindow else { return nil }
        let style = Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute()
        return "Evento \(start.formatted(style))"
    }

    /// mm:ss (acima de 99 min segue contando os minutos: "120:00").
    static func timerText(remaining: Int) -> String {
        let r = max(remaining, 0)
        return String(format: "%02d:%02d", r / 60, r % 60)
    }
}

/// Geometria pura do painel de widgets — a fração é o que o dono ajusta
/// depois de olhar (medido na demo do Alcove: o relógio termina ~40 %).
enum LockScreenLayout {
    /// Topo do painel, como fração da altura da tela a partir do topo.
    static let widgetsTopFraction: CGFloat = 0.46
    static let widgetsHeight: CGFloat = 40

    /// Frame em coordenadas AppKit (y pra cima): largura da tela, altura
    /// fixa, topo a `widgetsTopFraction` da altura. Não assume origem 0 —
    /// tela secundária tem frame deslocado (até negativo).
    static func widgetsFrame(screen: CGRect, height: CGFloat = widgetsHeight) -> CGRect {
        CGRect(x: screen.minX,
               y: screen.maxY - screen.height * widgetsTopFraction - height,
               width: screen.width, height: height)
    }
}
