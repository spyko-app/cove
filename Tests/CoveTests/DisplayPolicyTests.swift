import XCTest
@testable import Cove

final class DisplayPolicyTests: XCTestCase {
    func testOverrideTrueWinsOverGlobalExternalOnBuiltin() {
        let wants = DisplayPolicy.wantsPanel(
            uuid: "builtin-uuid", isBuiltin: true, global: "external",
            overrides: ["builtin-uuid": true])
        XCTAssertTrue(wants)
    }

    func testOverrideFalseHidesOnAll() {
        let wants = DisplayPolicy.wantsPanel(
            uuid: "ext-uuid", isBuiltin: false, global: "all",
            overrides: ["ext-uuid": false])
        XCTAssertFalse(wants)
    }

    func testNoOverrideFallsBackToGlobalModes() {
        XCTAssertTrue(DisplayPolicy.wantsPanel(uuid: "u1", isBuiltin: true, global: "all", overrides: [:]))
        XCTAssertTrue(DisplayPolicy.wantsPanel(uuid: "u1", isBuiltin: false, global: "all", overrides: [:]))

        XCTAssertTrue(DisplayPolicy.wantsPanel(uuid: "u1", isBuiltin: true, global: "builtin", overrides: [:]))
        XCTAssertFalse(DisplayPolicy.wantsPanel(uuid: "u1", isBuiltin: false, global: "builtin", overrides: [:]))

        XCTAssertFalse(DisplayPolicy.wantsPanel(uuid: "u1", isBuiltin: true, global: "external", overrides: [:]))
        XCTAssertTrue(DisplayPolicy.wantsPanel(uuid: "u1", isBuiltin: false, global: "external", overrides: [:]))
    }

    func testUnknownUUIDIgnored() {
        let wants = DisplayPolicy.wantsPanel(
            uuid: "u1", isBuiltin: true, global: "external",
            overrides: ["other-uuid": true])
        XCTAssertFalse(wants)
    }

    func testAnyVisibleTrueWhenAtLeastOneScreenQualifies() {
        let screens: [(uuid: String, isBuiltin: Bool)] = [("builtin-uuid", true), ("ext-uuid", false)]
        XCTAssertTrue(DisplayPolicy.anyVisible(screens: screens, global: "builtin", overrides: [:]))
    }

    func testAnyVisibleFalseWhenGlobalExcludesEveryScreen() {
        let screens: [(uuid: String, isBuiltin: Bool)] = [("builtin-uuid", true)]
        XCTAssertFalse(DisplayPolicy.anyVisible(screens: screens, global: "external", overrides: [:]))
    }

    func testAnyVisibleFalseWhenOverridesHideEverything() {
        let screens: [(uuid: String, isBuiltin: Bool)] = [("builtin-uuid", true), ("ext-uuid", false)]
        XCTAssertFalse(DisplayPolicy.anyVisible(
            screens: screens, global: "all",
            overrides: ["builtin-uuid": false, "ext-uuid": false]))
    }

    func testAnyVisibleTrueWhenOverrideRescuesOneScreen() {
        let screens: [(uuid: String, isBuiltin: Bool)] = [("builtin-uuid", true), ("ext-uuid", false)]
        XCTAssertTrue(DisplayPolicy.anyVisible(
            screens: screens, global: "external",
            overrides: ["builtin-uuid": true]))
    }
}
