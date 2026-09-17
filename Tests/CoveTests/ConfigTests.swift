import XCTest
@testable import Cove

final class ConfigTests: XCTestCase {
    func testDecodeTolerantToMissingAndUnknownKeys() throws {
        let json = #"{"hudDuration": 2.5, "displayOn": "external", "chaveFutura": true}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(NotchConfig.self, from: json)
        XCTAssertEqual(cfg.hudDuration, 2.5)
        XCTAssertEqual(cfg.displayOn, "external")
        XCTAssertTrue(cfg.showVolumeHUD)
    }

    func testRoundTrip() throws {
        var cfg = NotchConfig()
        cfg.hudStyle = "glow"
        cfg.verticalGestures = false
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(NotchConfig.self, from: data)
        XCTAssertEqual(back.hudStyle, "glow")
        XCTAssertFalse(back.verticalGestures)
    }

    func testDropletHotKeysRoundTrip() throws {
        var cfg = NotchConfig()
        cfg.dropletHotKeys = ["shelf": "ctrl+opt+1", "clipboard": "ctrl+opt+2"]
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(NotchConfig.self, from: data)
        XCTAssertEqual(back.dropletHotKeys, ["shelf": "ctrl+opt+1", "clipboard": "ctrl+opt+2"])
    }

    func testDropletHotKeysDefaultsToEmptyWhenMissing() throws {
        let json = #"{"hudDuration": 2.5}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(NotchConfig.self, from: json)
        XCTAssertEqual(cfg.dropletHotKeys, [:])
    }

    func testExpandActivityFlagsDefaultToTrue() throws {
        let json = #"{"hudDuration": 2.5}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(NotchConfig.self, from: json)
        XCTAssertTrue(cfg.expandActivityOnLongPress)
        XCTAssertTrue(cfg.expandActivityOnAlert)
    }

    func testExpandActivityFlagsRoundTrip() throws {
        var cfg = NotchConfig()
        cfg.expandActivityOnLongPress = false
        cfg.expandActivityOnAlert = false
        let back = try JSONDecoder().decode(NotchConfig.self, from: JSONEncoder().encode(cfg))
        XCTAssertFalse(back.expandActivityOnLongPress)
        XCTAssertFalse(back.expandActivityOnAlert)
    }

    func testActivityHUDClassification() {
        XCTAssertTrue(NotchActivity.volume(0.5, muted: false).isHUD)
        XCTAssertTrue(NotchActivity.keyboardBrightness(0.2).isHUD)
        XCTAssertFalse(NotchActivity.lock(true).isHUD)
        XCTAssertFalse(NotchActivity.event(title: "x", minutes: 1).isHUD)
    }

    func testDynamicGlassTintDefault() {
        XCTAssertEqual(NotchConfig().dynamicGlassTint, 0.55, accuracy: 0.0001)
    }

    func testDynamicGlassTintDefaultsWhenMissing() throws {
        let json = #"{"hudDuration": 2.5}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(NotchConfig.self, from: json)
        XCTAssertEqual(cfg.dynamicGlassTint, 0.55, accuracy: 0.0001)
    }

    func testDynamicGlassTintClampsOutOfRange() throws {
        let high = #"{"dynamicGlassTint": 1.7}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(NotchConfig.self, from: high).dynamicGlassTint, 1.0, accuracy: 0.0001)
        let low = #"{"dynamicGlassTint": -0.5}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(NotchConfig.self, from: low).dynamicGlassTint, 0.0, accuracy: 0.0001)
    }

    func testDynamicGlassTintRoundTrip() throws {
        var cfg = NotchConfig()
        cfg.dynamicGlassTint = 0.25
        let back = try JSONDecoder().decode(NotchConfig.self, from: try JSONEncoder().encode(cfg))
        XCTAssertEqual(back.dynamicGlassTint, 0.25, accuracy: 0.0001)
    }

    func testDynamicGlassOffByDefault() {
        XCTAssertFalse(NotchConfig().dynamicGlass)
    }

    func testDynamicGlassDefaultsToFalseWhenKeyMissing() throws {
        let json = #"{"hudDuration": 2.5}"#.data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(NotchConfig.self, from: json).dynamicGlass)
    }

    func testDynamicGlassRespectsExplicitTrue() throws {
        let json = #"{"dynamicGlass": true}"#.data(using: .utf8)!
        XCTAssertTrue(try JSONDecoder().decode(NotchConfig.self, from: json).dynamicGlass)
    }

    func testDynamicGlassRoundTripsFalse() throws {
        var cfg = NotchConfig()
        cfg.dynamicGlass = false
        let back = try JSONDecoder().decode(NotchConfig.self, from: try JSONEncoder().encode(cfg))
        XCTAssertFalse(back.dynamicGlass)
    }

    func testPullDownOpensSearchOnByDefault() {
        XCTAssertTrue(NotchConfig().pullDownOpensSearch)
    }

    func testPullDownOpensSearchDefaultsToTrueWhenKeyMissing() throws {
        let json = #"{"hudDuration": 2.5}"#.data(using: .utf8)!
        XCTAssertTrue(try JSONDecoder().decode(NotchConfig.self, from: json).pullDownOpensSearch)
    }

    func testPullDownOpensSearchRespectsExplicitFalse() throws {
        let json = #"{"pullDownOpensSearch": false}"#.data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(NotchConfig.self, from: json).pullDownOpensSearch)
    }

    func testShowOnLockScreenOnByDefault() {
        XCTAssertTrue(NotchConfig().showOnLockScreen)
    }

    func testShowOnLockScreenDefaultsToTrueWhenKeyMissing() throws {
        let json = #"{"hudDuration": 2.5}"#.data(using: .utf8)!
        XCTAssertTrue(try JSONDecoder().decode(NotchConfig.self, from: json).showOnLockScreen)
    }

    func testShowOnLockScreenRespectsExplicitFalse() throws {
        let json = #"{"showOnLockScreen": false}"#.data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(NotchConfig.self, from: json).showOnLockScreen)
    }

    func testShowOnLockScreenRoundTripsFalse() throws {
        var cfg = NotchConfig()
        cfg.showOnLockScreen = false
        let back = try JSONDecoder().decode(NotchConfig.self, from: try JSONEncoder().encode(cfg))
        XCTAssertFalse(back.showOnLockScreen)
    }
}
