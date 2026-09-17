import Foundation

enum LockScreenWidget: String, Codable, CaseIterable {
    case focus, weather, battery, media, calendar, timer

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

    static func decode(_ raw: [String]?) -> [LockScreenWidget] {
        guard let raw else { return defaults }
        return raw.compactMap(LockScreenWidget.init(rawValue:))
    }
}

struct LockScreenWidgetItem: Equatable, Identifiable {
    let kind: LockScreenWidget
    let symbol: String
    let text: String
    var id: LockScreenWidget { kind }
}

enum LockScreenWidgetsModel {
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
                if let m = media, m.isPlaying, !m.title.isEmpty {
                    let text = m.artist.isEmpty ? m.title : "\(m.title) · \(m.artist)"
                    out.append(.init(kind: kind, symbol: "music.note", text: text))
                }
            case .calendar:
                if let e = nextEvent, let t = eventText(start: e.start, now: now, timeZone: timeZone, locale: locale) {
                    out.append(.init(kind: kind, symbol: "calendar", text: t))
                }
            case .timer:
                if let s = timer, s.isRunning {
                    out.append(.init(kind: kind, symbol: "timer", text: timerText(remaining: s.remaining)))
                }
            }
        }
        return out
    }

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

    static func eventText(start: Date, now: Date, timeZone: TimeZone = .current,
                          locale: Locale = .current) -> String? {
        let delta = start.timeIntervalSince(now)
        guard delta > 0, delta <= eventWindow else { return nil }
        let style = Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute()
        return "Evento \(start.formatted(style))"
    }

    static func timerText(remaining: Int) -> String {
        let r = max(remaining, 0)
        return String(format: "%02d:%02d", r / 60, r % 60)
    }
}

enum LockScreenLayout {
    static let widgetsTopFraction: CGFloat = 0.46
    static let widgetsHeight: CGFloat = 40

    static func widgetsFrame(screen: CGRect, height: CGFloat = widgetsHeight) -> CGRect {
        CGRect(x: screen.minX,
               y: screen.maxY - screen.height * widgetsTopFraction - height,
               width: screen.width, height: height)
    }
}
