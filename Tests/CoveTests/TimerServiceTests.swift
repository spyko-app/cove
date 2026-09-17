import XCTest
@testable import Cove

@MainActor final class TimerServiceTests: XCTestCase {
    func testCountdownAndFinish() {
        let t = TimerService(autoTick: false)
        var finished: String?
        t.onFinished = { finished = $0 }
        let t0 = Date()
        t.start(label: "Foco", seconds: 3, now: t0)
        t.tick(now: t0.addingTimeInterval(1))
        XCTAssertEqual(t.session?.remaining, 2)
        t.tick(now: t0.addingTimeInterval(3.2))
        XCTAssertNil(t.session)
        XCTAssertEqual(finished, "Foco")
    }
    func testPauseResumeKeepsRemaining() {
        let t = TimerService(autoTick: false)
        let t0 = Date()
        t.start(label: "x", seconds: 10, now: t0)
        t.tick(now: t0.addingTimeInterval(4)); t.pause()
        t.tick(now: t0.addingTimeInterval(9))
        XCTAssertEqual(t.session?.remaining, 6)
        t.resume(now: t0.addingTimeInterval(9)); t.tick(now: t0.addingTimeInterval(10))
        XCTAssertEqual(t.session?.remaining, 5)
    }

    func testPomodoroFinishChainsBreak() {
        let t = TimerService(autoTick: false)
        t.onFinished = { label in
            if label == "Pomodoro" { t.start(label: "Pausa", seconds: TimerService.pomodoroBreak) }
        }
        let t0 = Date()
        t.start(label: "Pomodoro", seconds: 3, now: t0)
        t.tick(now: t0.addingTimeInterval(3.2))
        XCTAssertEqual(t.session?.label, "Pausa")
        XCTAssertEqual(t.session?.total, TimerService.pomodoroBreak)
    }

    func testExtendSomaNoTotalENoRestante() {
        let t = TimerService(autoTick: false)
        let t0 = Date()
        t.start(label: "Foco", seconds: 60, now: t0)
        t.extend(by: 300, now: t0)
        XCTAssertEqual(t.session?.total, 360)
        XCTAssertEqual(t.session?.remaining, 360)
        t.tick(now: t0.addingTimeInterval(60))
        XCTAssertEqual(t.session?.remaining, 300)
    }

    func testExtendSemSessaoOuComSegundosInvalidosNaoFazNada() {
        let t = TimerService(autoTick: false)
        t.extend(by: 300)
        XCTAssertNil(t.session)
        t.start(label: "Foco", seconds: 60)
        t.extend(by: 0)
        XCTAssertEqual(t.session?.total, 60)
    }
}
