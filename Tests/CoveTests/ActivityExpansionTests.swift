import XCTest
@testable import Cove

final class ActivityExpansionTests: XCTestCase {
    private func ids(_ a: NotchActivity, _ ctx: ActivityExpansion.Context = .init()) -> [String] {
        ActivityExpansion.actions(for: a, context: ctx).map(\.id)
    }

    func testTimerRodandoOferecePausarPararEMais5() {
        let ctx = ActivityExpansion.Context(timerRunning: true)
        let acts = ActivityExpansion.actions(for: .timer(label: "Pomodoro", remaining: 90), context: ctx)
        XCTAssertEqual(acts.map(\.id), ["timer.pause", "timer.stop", "timer.plus5"])
        XCTAssertEqual(acts[0].title, "Pausar")
        XCTAssertEqual(acts[2].action, .timerExtend(300))
    }

    func testTimerPausadoOfereceRetomar() {
        let ctx = ActivityExpansion.Context(timerRunning: false)
        let acts = ActivityExpansion.actions(for: .timer(label: "Foco", remaining: 30), context: ctx)
        XCTAssertEqual(acts[0].title, "Retomar")
        XCTAssertEqual(acts[0].action, .timerToggle)
    }

    func testHighAlertSoDesligar() {
        let acts = ActivityExpansion.actions(for: .highAlert(expiresAt: Date().addingTimeInterval(600)))
        XCTAssertEqual(acts.map(\.id), ["alert.stop"])
        XCTAssertEqual(acts[0].title, "Desligar")
    }

    func testEventoComLinkOfereceEntrar() {
        let url = URL(string: "https://meet.google.com/abc")!
        let acts = ActivityExpansion.actions(
            for: .eventCountdown(title: "Daily", start: Date().addingTimeInterval(300), meetingURL: url))
        XCTAssertEqual(acts.map(\.id), ["event.join", "event.snooze"])
        XCTAssertEqual(acts[0].action, .joinMeeting(url))
        XCTAssertEqual(acts[1].action, .snoozeEvent(300))
    }

    func testEventoSemLinkAbreNoCalendario() {
        let acts = ActivityExpansion.actions(
            for: .eventCountdown(title: "Daily", start: Date().addingTimeInterval(300), meetingURL: nil))
        XCTAssertEqual(acts.map(\.id), ["event.calendar", "event.snooze"])
        XCTAssertEqual(acts[0].action, .openCalendar)
    }

    func testEventoSimplesAbreCalendarioEAdia() {
        XCTAssertEqual(ids(.event(title: "Reunião", minutes: 8)), ["event.calendar", "event.snooze"])
    }

    func testNotificacaoResponderEAbrir() {
        let acts = ActivityExpansion.actions(for: .notification(app: "Mensagens", title: "oi"))
        XCTAssertEqual(acts.map(\.action), [.replyNotification, .openNotifications])
    }

    func testDispositivoConectadoTrocaSaidaEDesconectadoNaoTemAcao() {
        XCTAssertEqual(ids(.device(name: "AirPods Pro", connected: true, battery: 72)), ["device.output"])
        XCTAssertTrue(ids(.device(name: "AirPods Pro", connected: false)).isEmpty)
    }

    func testBateriaAbrePainelDoSistema() {
        let acts = ActivityExpansion.actions(for: .battery(.init(percent: 8, charging: false, onAC: false)))
        XCTAssertEqual(acts.map(\.action), [.openBatterySettings])
        XCTAssertTrue(ActivityExpansion.batterySettingsURL.hasPrefix("x-apple.systempreferences:"))
    }

    func testGravacoesOferecemParar() {
        XCTAssertEqual(ids(.recording(elapsed: 12)).first, "rec.stop")
        XCTAssertEqual(ids(.screenRecording(elapsed: 12)).first, "screenrec.stop")
    }

    func testVPNSemAcao() {
        XCTAssertTrue(ids(.vpn(up: false)).isEmpty)
        XCTAssertTrue(ids(.vpnSession(since: Date())).isEmpty)
    }

    func testTiposSemAcaoTemBottomVazio() {
        XCTAssertTrue(ids(.volume(0.5, muted: false)).isEmpty)
        XCTAssertTrue(ids(.brightness(0.8)).isEmpty)
        XCTAssertTrue(ids(.focus(true)).isEmpty)
        XCTAssertTrue(ids(.lock(true)).isEmpty)
        XCTAssertTrue(ids(.wifi(ssid: "Cove", connected: true)).isEmpty)
        XCTAssertTrue(ids(.track(title: "t", artist: "a")).isEmpty)
    }

    func testBateriaAlertaAte10PorCentoSemTomada() {
        XCTAssertTrue(ActivityExpansion.isAlerting(.battery(.init(percent: 10, charging: false, onAC: false))))
        XCTAssertFalse(ActivityExpansion.isAlerting(.battery(.init(percent: 11, charging: false, onAC: false))))
        XCTAssertFalse(ActivityExpansion.isAlerting(.battery(.init(percent: 5, charging: true, onAC: true))))
    }

    func testCountdownAlertaAte1Minuto() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let ctx = ActivityExpansion.Context(now: now)
        let em30s = NotchActivity.eventCountdown(title: "Daily", start: now.addingTimeInterval(30), meetingURL: nil)
        let em5min = NotchActivity.eventCountdown(title: "Daily", start: now.addingTimeInterval(300), meetingURL: nil)
        XCTAssertTrue(ActivityExpansion.isAlerting(em30s, context: ctx))
        XCTAssertFalse(ActivityExpansion.isAlerting(em5min, context: ctx))
    }

    func testVPNDesconectadaAlerta() {
        XCTAssertTrue(ActivityExpansion.isAlerting(.vpn(up: false)))
        XCTAssertFalse(ActivityExpansion.isAlerting(.vpn(up: true)))
    }

    func testGravacaoSoAlertaQuandoParouPorErro() {
        let ok = ActivityExpansion.Context()
        let falhou = ActivityExpansion.Context(recordingFailed: true)
        XCTAssertFalse(ActivityExpansion.isAlerting(.screenRecording(elapsed: 5), context: ok))
        XCTAssertTrue(ActivityExpansion.isAlerting(.screenRecording(elapsed: 5), context: falhou))
        XCTAssertTrue(ActivityExpansion.isAlerting(.recording(elapsed: 5), context: falhou))
    }

    func testTiposComunsNaoAlertam() {
        XCTAssertFalse(ActivityExpansion.isAlerting(.volume(0.5, muted: false)))
        XCTAssertFalse(ActivityExpansion.isAlerting(.timer(label: "Pomodoro", remaining: 10)))
        XCTAssertFalse(ActivityExpansion.isAlerting(.notification(app: "X", title: "y")))
    }

    func testRegioesDoTimer() {
        let ctx = ActivityExpansion.Context(timerRunning: true)
        let r = ActivityExpansion.regions(for: .timer(label: "Pomodoro", remaining: 125), context: ctx)
        XCTAssertEqual(r.symbol, "timer")
        XCTAssertEqual(r.title, "Pomodoro")
        XCTAssertEqual(r.subtitle, "Em andamento")
        XCTAssertEqual(r.value, "02:05")
        XCTAssertEqual(r.actions.count, 3)
    }

    func testRegioesDaBateriaBaixaSaoVermelhas() {
        let r = ActivityExpansion.regions(for: .battery(.init(percent: 8, charging: false, onAC: false)))
        XCTAssertEqual(r.tint, .red)
        XCTAssertEqual(r.value, "8%")
    }

    func testMMSSPassaDeUmaHora() {
        XCTAssertEqual(ActivityExpansion.mmss(59), "00:59")
        XCTAssertEqual(ActivityExpansion.mmss(3661), "1:01:01")
        XCTAssertEqual(ActivityExpansion.mmss(-5), "00:00")
    }
}
