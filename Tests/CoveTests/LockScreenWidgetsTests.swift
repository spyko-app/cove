import XCTest
@testable import Cove

/// Modelo puro dos widgets da tela de bloqueio (estilo Alcove): quais
/// aparecem, em que ordem, com que texto — sem serviço nenhum por trás.
final class LockScreenWidgetsTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    /// Locale por identificador NÃO herda a preferência 12/24 h do sistema → determinístico.
    private let ptBR = Locale(identifier: "pt_BR")
    private let now = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 22:13:20 UTC

    private func items(config: [LockScreenWidget] = LockScreenWidget.allCases,
                       focus: Bool = false,
                       weather: WeatherService.Weather? = nil,
                       battery: PowerService.BatteryState? = nil,
                       media: NowPlaying? = nil,
                       event: CalendarService.UpcomingEvent? = nil,
                       timer: TimerService.Session? = nil) -> [LockScreenWidgetItem] {
        LockScreenWidgetsModel.items(config: config, focusActive: focus, weather: weather, battery: battery,
                                     media: media, nextEvent: event, timer: timer, now: now, timeZone: utc, locale: ptBR)
    }

    // MARK: - habilitação / omissão sem dado

    func testNothingEnabledYieldsNothing() {
        let all = items(config: [], focus: true, weather: .init(tempC: 20, code: 0),
                        battery: .init(percent: 50, charging: false, onAC: false))
        XCTAssertTrue(all.isEmpty)
    }

    func testEnabledWithoutDataIsOmitted() {
        // tudo ligado, nada com dado (foco off, sem clima, sem bateria, sem mídia, sem evento, sem timer)
        XCTAssertTrue(items().isEmpty)
    }

    func testOnlyEnabledKindsAppear() {
        let out = items(config: [.battery], focus: true, weather: .init(tempC: 20, code: 0),
                        battery: .init(percent: 50, charging: false, onAC: false))
        XCTAssertEqual(out.map(\.kind), [.battery])
    }

    // MARK: - ordem canônica (o array da config é só o conjunto ligado)

    func testOrderIsCanonicalRegardlessOfConfigOrder() {
        let out = items(config: [.battery, .focus, .weather], focus: true, weather: .init(tempC: 16, code: 1),
                        battery: .init(percent: 86, charging: false, onAC: false))
        XCTAssertEqual(out.map(\.kind), [.focus, .weather, .battery])
    }

    func testDefaultsAreFocusWeatherBatteryMedia() {
        XCTAssertEqual(LockScreenWidget.defaults, [.focus, .weather, .battery, .media])
    }

    // MARK: - textos

    func testFocusIsGenericLabelWithMoon() {
        let out = items(config: [.focus], focus: true)
        XCTAssertEqual(out, [.init(kind: .focus, symbol: "moon.fill", text: "Foco")])
    }

    func testWeatherRoundsTemperatureAndUsesServiceSymbol() {
        let out = items(config: [.weather], weather: .init(tempC: 16.4, code: 3))
        XCTAssertEqual(out.first?.text, "16°")
        XCTAssertEqual(out.first?.symbol, "cloud.fill")
        XCTAssertEqual(items(config: [.weather], weather: .init(tempC: 16.6, code: 0)).first?.text, "17°")
    }

    func testBatteryPercentText() {
        let out = items(config: [.battery], battery: .init(percent: 86, charging: false, onAC: false))
        XCTAssertEqual(out.first?.text, "86%")
        XCTAssertEqual(out.first?.symbol, "battery.75percent")
    }

    func testBatterySymbolByRange() {
        XCTAssertEqual(LockScreenWidgetsModel.batterySymbol(percent: 100, plugged: false), "battery.100percent")
        XCTAssertEqual(LockScreenWidgetsModel.batterySymbol(percent: 90, plugged: false), "battery.100percent")
        XCTAssertEqual(LockScreenWidgetsModel.batterySymbol(percent: 89, plugged: false), "battery.75percent")
        XCTAssertEqual(LockScreenWidgetsModel.batterySymbol(percent: 60, plugged: false), "battery.75percent")
        XCTAssertEqual(LockScreenWidgetsModel.batterySymbol(percent: 59, plugged: false), "battery.50percent")
        XCTAssertEqual(LockScreenWidgetsModel.batterySymbol(percent: 35, plugged: false), "battery.50percent")
        XCTAssertEqual(LockScreenWidgetsModel.batterySymbol(percent: 34, plugged: false), "battery.25percent")
        XCTAssertEqual(LockScreenWidgetsModel.batterySymbol(percent: 10, plugged: false), "battery.25percent")
        XCTAssertEqual(LockScreenWidgetsModel.batterySymbol(percent: 9, plugged: false), "battery.0percent")
        XCTAssertEqual(LockScreenWidgetsModel.batterySymbol(percent: 0, plugged: false), "battery.0percent")
    }

    func testBatteryBoltWhenPluggedEvenAtFullCharge() {
        // 100 % na tomada: `charging` é false, `onAC` true → raio mesmo assim
        let full = items(config: [.battery], battery: .init(percent: 100, charging: false, onAC: true))
        XCTAssertEqual(full.first?.symbol, "battery.100percent.bolt")
        let charging = items(config: [.battery], battery: .init(percent: 40, charging: true, onAC: false))
        XCTAssertEqual(charging.first?.symbol, "battery.100percent.bolt")
    }

    func testMediaOnlyWhilePlaying() {
        var np = NowPlaying()
        np.title = "Song"; np.artist = "Band"; np.isPlaying = false
        XCTAssertTrue(items(config: [.media], media: np).isEmpty)
        np.isPlaying = true
        XCTAssertEqual(items(config: [.media], media: np).first?.text, "Song · Band")
        XCTAssertEqual(items(config: [.media], media: np).first?.symbol, "music.note")
    }

    func testMediaWithoutArtistShowsOnlyTitle() {
        var np = NowPlaying()
        np.title = "Podcast"; np.isPlaying = true
        XCTAssertEqual(items(config: [.media], media: np).first?.text, "Podcast")
    }

    func testMediaWithEmptyTitleOmitted() {
        var np = NowPlaying()
        np.isPlaying = true
        XCTAssertTrue(items(config: [.media], media: np).isEmpty)
    }

    // MARK: - evento: título genérico (privacidade), só futuro e ≤ 12 h

    func testEventTitleIsGenericWithTime() {
        let start = now.addingTimeInterval(2 * 3600)   // 00:13 UTC do dia seguinte
        let ev = CalendarService.UpcomingEvent(title: "Entrevista — Empresa X", start: start)
        let out = items(config: [.calendar], event: ev)
        XCTAssertEqual(out, [.init(kind: .calendar, symbol: "calendar", text: "Evento 00:13")])
        XCTAssertFalse(out.first!.text.contains("Entrevista"))
    }

    func testEventBeyondTwelveHoursOmitted() {
        let ev = CalendarService.UpcomingEvent(title: "X", start: now.addingTimeInterval(12 * 3600 + 1))
        XCTAssertTrue(items(config: [.calendar], event: ev).isEmpty)
        let edge = CalendarService.UpcomingEvent(title: "X", start: now.addingTimeInterval(12 * 3600))
        XCTAssertEqual(items(config: [.calendar], event: edge).count, 1)
    }

    func testEventAlreadyStartedOmitted() {
        let ev = CalendarService.UpcomingEvent(title: "X", start: now.addingTimeInterval(-60))
        XCTAssertTrue(items(config: [.calendar], event: ev).isEmpty)
    }

    func testEventTextUsesGivenTimeZone() {
        let start = now.addingTimeInterval(3600)   // 23:13 UTC
        XCTAssertEqual(LockScreenWidgetsModel.eventText(start: start, now: now, timeZone: utc, locale: ptBR), "Evento 23:13")
        let sp = TimeZone(identifier: "America/Sao_Paulo")!   // UTC-3
        XCTAssertEqual(LockScreenWidgetsModel.eventText(start: start, now: now, timeZone: sp, locale: ptBR), "Evento 20:13")
    }

    func testEventTextFollowsLocaleHourCycle() throws {
        // 12 h em en_US como o relógio do lock (o separador antes de PM é U+202F, não espaço)
        let start = now.addingTimeInterval(3600)   // 23:13 UTC
        let text = try XCTUnwrap(LockScreenWidgetsModel.eventText(start: start, now: now, timeZone: utc,
                                                                  locale: Locale(identifier: "en_US")))
        XCTAssertTrue(text.hasPrefix("Evento 11:13"), text)
        XCTAssertTrue(text.hasSuffix("PM"), text)
        XCTAssertFalse(text.contains("23:13"))
    }

    // MARK: - timer

    func testTimerFormatsMinutesSeconds() {
        XCTAssertEqual(LockScreenWidgetsModel.timerText(remaining: 0), "00:00")
        XCTAssertEqual(LockScreenWidgetsModel.timerText(remaining: 65), "01:05")
        XCTAssertEqual(LockScreenWidgetsModel.timerText(remaining: 25 * 60), "25:00")
        XCTAssertEqual(LockScreenWidgetsModel.timerText(remaining: 120 * 60), "120:00")
        XCTAssertEqual(LockScreenWidgetsModel.timerText(remaining: -5), "00:00")
    }

    func testTimerItemUsesRemainingNotLabel() {
        let s = TimerService.Session(label: "ligar pro banco", total: 300, remaining: 90, isRunning: true)
        let out = items(config: [.timer], timer: s)
        XCTAssertEqual(out, [.init(kind: .timer, symbol: "timer", text: "01:30")])
    }

    func testTimerPausedIsOmitted() {
        // pausado ao lado do relógio pareceria contagem viva — some, como na ilha
        let s = TimerService.Session(label: "x", total: 300, remaining: 90, isRunning: false)
        XCTAssertTrue(items(config: [.timer], timer: s).isEmpty)
    }

    // MARK: - config: decode tolerante

    func testDecodeMissingKeyGivesDefaults() throws {
        let cfg = try JSONDecoder().decode(NotchConfig.self, from: #"{"hudDuration": 2}"#.data(using: .utf8)!)
        XCTAssertEqual(cfg.lockScreenWidgets, LockScreenWidget.defaults)
    }

    func testDecodeIgnoresUnknownValueKeepsKnown() throws {
        let json = #"{"lockScreenWidgets": ["weather", "hologram", "timer"]}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(NotchConfig.self, from: json)
        XCTAssertEqual(cfg.lockScreenWidgets, [.weather, .timer])
        XCTAssertTrue(cfg.showVolumeHUD)   // resto do config intacto
    }

    func testDecodeExplicitEmptyStaysEmpty() throws {
        let cfg = try JSONDecoder().decode(NotchConfig.self, from: #"{"lockScreenWidgets": []}"#.data(using: .utf8)!)
        XCTAssertEqual(cfg.lockScreenWidgets, [])
    }

    func testRoundTrip() throws {
        var cfg = NotchConfig()
        cfg.lockScreenWidgets = [.calendar, .timer]
        let back = try JSONDecoder().decode(NotchConfig.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back.lockScreenWidgets, [.calendar, .timer])
    }

    func testDecodeHelperDirect() {
        XCTAssertEqual(LockScreenWidget.decode(nil), LockScreenWidget.defaults)
        XCTAssertEqual(LockScreenWidget.decode(["x"]), [])
        XCTAssertEqual(LockScreenWidget.decode(["focus", "focus"]), [.focus, .focus])
    }

    // MARK: - layout

    func testWidgetsTopFraction() {
        XCTAssertEqual(LockScreenLayout.widgetsTopFraction, 0.46, accuracy: 0.0001)
        XCTAssertEqual(LockScreenLayout.widgetsHeight, 40)
    }

    func testWidgetsFrameOnMainScreen() {
        let f = LockScreenLayout.widgetsFrame(screen: CGRect(x: 0, y: 0, width: 1512, height: 982))
        XCTAssertEqual(f.minX, 0); XCTAssertEqual(f.width, 1512); XCTAssertEqual(f.height, 40)
        // topo a 46 % da altura, contado do topo: maxY = 982 − 451.72
        XCTAssertEqual(f.maxY, 982 - 982 * 0.46, accuracy: 0.001)
    }

    func testWidgetsFrameOnOffsetScreen() {
        let f = LockScreenLayout.widgetsFrame(screen: CGRect(x: -1920, y: -200, width: 1920, height: 1080), height: 40)
        XCTAssertEqual(f.minX, -1920)
        XCTAssertEqual(f.maxY, 880 - 1080 * 0.46, accuracy: 0.001)
        XCTAssertEqual(f.height, 40)
    }
}
