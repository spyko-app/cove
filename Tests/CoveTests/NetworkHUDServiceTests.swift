import XCTest
@testable import Cove

@MainActor final class NetworkHUDServiceTests: XCTestCase {
    func testWifiConnectEmitsActivity() {
        let previous = NetworkHUDService.NetState(wifiPowered: true, wifiSSID: nil)
        let next = NetworkHUDService.NetState(wifiPowered: true, wifiSSID: "Cove-5G")
        XCTAssertEqual(NetworkHUDService.activity(previous: previous, next: next),
                        .wifi(ssid: "Cove-5G", connected: true))
    }

    func testWifiDisconnectEmitsActivity() {
        let previous = NetworkHUDService.NetState(wifiPowered: true, wifiSSID: "Cove-5G")
        let next = NetworkHUDService.NetState(wifiPowered: true, wifiSSID: nil)
        XCTAssertEqual(NetworkHUDService.activity(previous: previous, next: next),
                        .wifi(ssid: nil, connected: false))
    }

    func testSameSSIDTwiceEmitsNothing() {
        let previous = NetworkHUDService.NetState(wifiPowered: true, wifiSSID: "Cove-5G")
        let next = NetworkHUDService.NetState(wifiPowered: true, wifiSSID: "Cove-5G")
        XCTAssertNil(NetworkHUDService.activity(previous: previous, next: next))
    }

    func testWifiPowerOffEmitsActivity() {
        let previous = NetworkHUDService.NetState(wifiPowered: true, wifiSSID: "Cove-5G")
        let next = NetworkHUDService.NetState(wifiPowered: false, wifiSSID: "Cove-5G")
        XCTAssertEqual(NetworkHUDService.activity(previous: previous, next: next),
                        .wifi(ssid: nil, connected: false))
    }

    func testWifiPowerOnEmitsActivityWithSSID() {
        let previous = NetworkHUDService.NetState(wifiPowered: false, wifiSSID: nil)
        let next = NetworkHUDService.NetState(wifiPowered: true, wifiSSID: "Cove-5G")
        XCTAssertEqual(NetworkHUDService.activity(previous: previous, next: next),
                        .wifi(ssid: "Cove-5G", connected: true))
    }

    func testHotspotOnEmitsActivity() {
        let previous = NetworkHUDService.NetState(hotspotOn: false)
        let next = NetworkHUDService.NetState(hotspotOn: true)
        XCTAssertEqual(NetworkHUDService.activity(previous: previous, next: next),
                        .hotspot(on: true))
    }

    func testHotspotOffEmitsActivity() {
        let previous = NetworkHUDService.NetState(hotspotOn: true)
        let next = NetworkHUDService.NetState(hotspotOn: false)
        XCTAssertEqual(NetworkHUDService.activity(previous: previous, next: next),
                        .hotspot(on: false))
    }

    func testDriveMountEmitsActivity() {
        let previous = NetworkHUDService.NetState(mountedDrives: [])
        let next = NetworkHUDService.NetState(mountedDrives: ["Pendrive Cove"])
        XCTAssertEqual(NetworkHUDService.activity(previous: previous, next: next),
                        .drive(name: "Pendrive Cove", mounted: true))
    }

    func testDriveUnmountEmitsActivity() {
        let previous = NetworkHUDService.NetState(mountedDrives: ["Pendrive Cove"])
        let next = NetworkHUDService.NetState(mountedDrives: [])
        XCTAssertEqual(NetworkHUDService.activity(previous: previous, next: next),
                        .drive(name: "Pendrive Cove", mounted: false))
    }

    func testIdenticalStateEmitsNothing() {
        let s = NetworkHUDService.NetState(wifiPowered: true, wifiSSID: "Cove-5G",
                                            hotspotOn: false, mountedDrives: ["HD"])
        XCTAssertNil(NetworkHUDService.activity(previous: s, next: s))
    }

    func testShouldReportRemovableLocalAfterGraceWindow() {
        XCTAssertTrue(NetworkHUDService.shouldReport(
            removable: true, ejectable: false, local: true, sinceLaunch: 10))
    }

    func testShouldReportRejectsDuringBootGraceWindow() {
        XCTAssertFalse(NetworkHUDService.shouldReport(
            removable: true, ejectable: false, local: true, sinceLaunch: 1))
    }

    func testShouldReportRejectsNetworkShare() {
        XCTAssertFalse(NetworkHUDService.shouldReport(
            removable: false, ejectable: false, local: false, sinceLaunch: 10))
    }

    func testShouldReportRejectsFixedLocalVolume() {
        XCTAssertFalse(NetworkHUDService.shouldReport(
            removable: false, ejectable: false, local: true, sinceLaunch: 10))
    }

    func testIsHotspotInterfaceDetectsBridgeUpWithIPv4() {
        XCTAssertTrue(NetworkHUDService.isHotspotInterface(name: "bridge100", isUp: true, hasIPv4: true))
    }

    func testIsHotspotInterfaceRejectsNonBridgeName() {
        XCTAssertFalse(NetworkHUDService.isHotspotInterface(name: "en0", isUp: true, hasIPv4: true))
    }

    func testIsHotspotInterfaceRejectsDownBridge() {
        XCTAssertFalse(NetworkHUDService.isHotspotInterface(name: "bridge100", isUp: false, hasIPv4: true))
    }

    func testIsHotspotInterfaceRejectsBridgeWithoutIPv4() {
        XCTAssertFalse(NetworkHUDService.isHotspotInterface(name: "bridge100", isUp: true, hasIPv4: false))
    }
}
