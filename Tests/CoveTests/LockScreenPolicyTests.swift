import XCTest
@testable import Cove

/// A bridge SkyLight em si não é testável sem WindowServer — só a regra pura
/// de quando delegar os painéis ao space da tela de bloqueio.
final class LockScreenPolicyTests: XCTestCase {
    func testDelegatesOnlyWhenLockedEnabledAndBridgeAvailable() {
        XCTAssertTrue(LockScreenPolicy.shouldDelegate(locked: true, enabled: true, bridgeAvailable: true))
    }

    func testUnlockedNeverDelegates() {
        XCTAssertFalse(LockScreenPolicy.shouldDelegate(locked: false, enabled: true, bridgeAvailable: true))
    }

    func testToggleOffNeverDelegates() {
        XCTAssertFalse(LockScreenPolicy.shouldDelegate(locked: true, enabled: false, bridgeAvailable: true))
    }

    func testMissingBridgeDegradesSilently() {
        XCTAssertFalse(LockScreenPolicy.shouldDelegate(locked: true, enabled: true, bridgeAvailable: false))
    }

    func testAllOffIsFalse() {
        XCTAssertFalse(LockScreenPolicy.shouldDelegate(locked: false, enabled: false, bridgeAvailable: false))
    }

    // MARK: - allowsPeek: notificação nunca sobe por cima do loginwindow

    func testNotificationPeekBlockedWhileLocked() {
        XCTAssertFalse(LockScreenPolicy.allowsPeek(kindKey: "notification", locked: true))
    }

    func testNotificationPeekAllowedWhenUnlocked() {
        XCTAssertTrue(LockScreenPolicy.allowsPeek(kindKey: "notification", locked: false))
    }

    func testOtherKindsStillPeekWhileLocked() {
        for key in ["volume", "brightness", "battery", "lowPowerMode", "lock", "track",
                    "event", "eventCountdown", "device", "drive", "wifi", "timer"] {
            XCTAssertTrue(LockScreenPolicy.allowsPeek(kindKey: key, locked: true), key)
        }
    }

    func testAllowsPeekMatchesRealKindKey() {
        let a = NotchActivity.notification(app: "Mensagens", title: "oi")
        XCTAssertFalse(LockScreenPolicy.allowsPeek(kindKey: a.kindKey, locked: true))
    }

    // MARK: - redactedForLockScreen: texto livre vira genérico, payload fica

    func testEventTitleRedacted() {
        XCTAssertEqual(NotchActivity.event(title: "Entrevista — Empresa X", minutes: 8).redactedForLockScreen,
                       .event(title: "Evento", minutes: 8))
    }

    func testEventCountdownKeepsStartAndMeetingURL() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let url = URL(string: "https://meet.example/abc")!
        XCTAssertEqual(NotchActivity.eventCountdown(title: "1:1 com o chefe", start: start, meetingURL: url)
                           .redactedForLockScreen,
                       .eventCountdown(title: "Evento", start: start, meetingURL: url))
    }

    func testTimerLabelRedactedKeepsRemaining() {
        XCTAssertEqual(NotchActivity.timer(label: "ligar pro banco", remaining: 90).redactedForLockScreen,
                       .timer(label: "", remaining: 90))
    }

    func testDriveNameRedacted() {
        XCTAssertEqual(NotchActivity.drive(name: "Backup Banco", mounted: true).redactedForLockScreen,
                       .drive(name: "Disco", mounted: true))
        XCTAssertEqual(NotchActivity.drive(name: "Backup Banco", mounted: false).redactedForLockScreen,
                       .drive(name: "Disco", mounted: false))
    }

    func testDeviceNameRedactedKeepsBattery() {
        XCTAssertEqual(NotchActivity.device(name: "AirPods de Mateus", connected: true, battery: 72)
                           .redactedForLockScreen,
                       .device(name: "Dispositivo", connected: true, battery: 72))
    }

    func testWifiSSIDDropped() {
        XCTAssertEqual(NotchActivity.wifi(ssid: "Casa-5G", connected: true).redactedForLockScreen,
                       .wifi(ssid: nil, connected: true))
    }

    func testNotificationTitleEmptied() {
        XCTAssertEqual(NotchActivity.notification(app: "Mensagens", title: "bora fechar?").redactedForLockScreen,
                       .notification(app: "Mensagens", title: ""))
    }

    func testNonTextualActivitiesUntouched() {
        let untouched: [NotchActivity] = [
            .volume(0.5, muted: false), .brightness(0.3), .keyboardBrightness(0.1),
            .lowPowerMode(true), .focus(true), .lock(true), .hotspot(on: true),
            .vpn(up: false), .recording(elapsed: 12), .screenRecording(elapsed: 3),
            .track(title: "Song", artist: "Band"),
        ]
        for a in untouched {
            XCTAssertEqual(a.redactedForLockScreen, a, a.kindKey)
        }
    }

    func testRedactionIsIdempotent() {
        let a = NotchActivity.event(title: "X", minutes: 1).redactedForLockScreen
        XCTAssertEqual(a.redactedForLockScreen, a)
    }

    func testRedactionPreservesKindKey() {
        let all: [NotchActivity] = [
            .event(title: "X", minutes: 1),
            .eventCountdown(title: "X", start: Date(), meetingURL: nil),
            .timer(label: "X", remaining: 1),
            .drive(name: "X", mounted: true),
            .device(name: "X", connected: true),
            .wifi(ssid: "X", connected: true),
            .notification(app: "X", title: "Y"),
        ]
        for a in all { XCTAssertEqual(a.redactedForLockScreen.kindKey, a.kindKey) }
    }
}
