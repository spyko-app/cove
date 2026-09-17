import XCTest
@testable import Cove

final class WideIslandLayoutTests: XCTestCase {

    // MARK: - Matriz mode × simulated

    func testIsWideMatrix() {
        XCTAssertFalse(WideIslandLayout.isWide(mode: .off, simulated: false))
        XCTAssertFalse(WideIslandLayout.isWide(mode: .off, simulated: true))
        XCTAssertFalse(WideIslandLayout.isWide(mode: .externalOnly, simulated: false))
        XCTAssertTrue(WideIslandLayout.isWide(mode: .externalOnly, simulated: true))
        XCTAssertTrue(WideIslandLayout.isWide(mode: .always, simulated: false))
        XCTAssertTrue(WideIslandLayout.isWide(mode: .always, simulated: true))
    }

    func testExtraWidth() {
        XCTAssertEqual(WideIslandLayout.extraWidth, 120)
    }

    // MARK: - Config

    func testConfigDefaultIsExternalOnly() throws {
        XCTAssertEqual(NotchConfig().wideIsland, .externalOnly)
        let cfg = try JSONDecoder().decode(NotchConfig.self, from: #"{}"#.data(using: .utf8)!)
        XCTAssertEqual(cfg.wideIsland, .externalOnly)
    }

    func testConfigDecodesKnownValue() throws {
        let cfg = try JSONDecoder().decode(
            NotchConfig.self, from: #"{"wideIsland":"always"}"#.data(using: .utf8)!)
        XCTAssertEqual(cfg.wideIsland, .always)
    }

    /// rawValue desconhecido NÃO pode lançar: o `try?` do store devolveria o
    /// config inteiro no default e o dono perderia todos os ajustes.
    func testConfigUnknownValueFallsBackWithoutThrowing() throws {
        let cfg = try JSONDecoder().decode(
            NotchConfig.self, from: #"{"wideIsland":"banana","hudStyle":"glow"}"#.data(using: .utf8)!)
        XCTAssertEqual(cfg.wideIsland, .externalOnly)
        XCTAssertEqual(cfg.hudStyle, "glow")   // resto do config sobreviveu
    }

    func testConfigWrongTypeFallsBack() throws {
        let cfg = try JSONDecoder().decode(
            NotchConfig.self, from: #"{"wideIsland":3}"#.data(using: .utf8)!)
        XCTAssertEqual(cfg.wideIsland, .externalOnly)
    }

    func testConfigRoundTrip() throws {
        var cfg = NotchConfig()
        cfg.wideIsland = .off
        let back = try JSONDecoder().decode(NotchConfig.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back.wideIsland, .off)
    }

    // MARK: - Seletor de conteúdo

    func testPickNothing() {
        XCTAssertNil(WideIslandContent.pick(media: false, activity: nil))
    }

    func testPickMediaOnly() {
        XCTAssertEqual(WideIslandContent.pick(media: true, activity: nil), .media)
    }

    func testPickActivityOnly() {
        let a = NotchActivity.timer(label: "Pomodoro", remaining: 90)
        XCTAssertEqual(WideIslandContent.pick(media: false, activity: a), .activity(a))
    }

    /// Mídia E atividade: a atividade (o que muda) à direita, arte à esquerda.
    func testPickMediaAndActivity() {
        let a = NotchActivity.recording(elapsed: 12)
        XCTAssertEqual(WideIslandContent.pick(media: true, activity: a), .mediaAndActivity(a))
    }

    /// Atividade não elegível (HUD de volume) é ignorada pelo seletor.
    func testPickIgnoresNonWideActivity() {
        XCTAssertEqual(WideIslandContent.pick(media: true, activity: .volume(0.5, muted: false)), .media)
        XCTAssertNil(WideIslandContent.pick(media: false, activity: .volume(0.5, muted: false)))
    }

    func testWideActivityKinds() {
        XCTAssertTrue(WideIslandContent.isWideActivity(.timer(label: "Timer", remaining: 1)))
        XCTAssertTrue(WideIslandContent.isWideActivity(.highAlert(expiresAt: Date())))
        XCTAssertTrue(WideIslandContent.isWideActivity(.recording(elapsed: 1)))
        XCTAssertTrue(WideIslandContent.isWideActivity(.screenRecording(elapsed: 1)))
        XCTAssertTrue(WideIslandContent.isWideActivity(.vpnSession(since: Date())))
        XCTAssertTrue(WideIslandContent.isWideActivity(
            .eventCountdown(title: "Daily", start: Date(), meetingURL: nil)))
        XCTAssertFalse(WideIslandContent.isWideActivity(.brightness(0.4)))
        XCTAssertFalse(WideIslandContent.isWideActivity(.track(title: "a", artist: "b")))
    }

    /// A chave de animação não pode mudar com o payload (mm:ss muda a cada
    /// segundo — senão o spring de largura re-dispara a cada tick).
    func testAnimationKeyIsStableAcrossPayloadTicks() {
        let a = WideIslandContent.activity(.timer(label: "Foco", remaining: 90))
        let b = WideIslandContent.activity(.timer(label: "Foco", remaining: 89))
        XCTAssertEqual(a.animationKey, b.animationKey)
        XCTAssertNotEqual(a.animationKey, WideIslandContent.media.animationKey)
        XCTAssertNotEqual(a.animationKey,
                          WideIslandContent.mediaAndActivity(.timer(label: "Foco", remaining: 90)).animationKey)
    }

    // MARK: - Rótulos

    func testLabels() {
        XCTAssertEqual(WideIslandLayout.label(for: .timer(label: "Pomodoro", remaining: 60)), "Pomodoro")
        XCTAssertEqual(WideIslandLayout.label(for: .timer(label: "", remaining: 60)), "Timer")
        XCTAssertEqual(WideIslandLayout.label(for: .highAlert(expiresAt: Date())), "High Alert")
        XCTAssertEqual(WideIslandLayout.label(for: .recording(elapsed: 3)), "Gravando")
        XCTAssertEqual(WideIslandLayout.label(for: .screenRecording(elapsed: 3)), "Gravando tela")
        XCTAssertEqual(WideIslandLayout.label(for: .vpnSession(since: Date())), "VPN")
        XCTAssertEqual(WideIslandLayout.label(
            for: .eventCountdown(title: "Reunião", start: Date(), meetingURL: nil)), "Reunião")
    }
}
