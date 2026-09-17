import XCTest
@testable import Cove

@MainActor final class VPNMonitorTests: XCTestCase {
    func testVPNUpEmitsEvent() {
        XCTAssertEqual(VPNMonitor.transition(previous: false, activeInterfaces: ["utun3"]), .up)
    }

    func testVPNStillUpEmitsNothing() {
        XCTAssertNil(VPNMonitor.transition(previous: true, activeInterfaces: ["utun3"]))
    }

    func testVPNDuplicateInterfaceKeyEmitsNothing() {
        let names = VPNMonitor.interfaceNames(fromKeys: [
            "State:/Network/Interface/utun3/IPv4",
            "State:/Network/Interface/utun3/IPv6",
        ])
        XCTAssertEqual(Set(names), ["utun3"])
        XCTAssertNil(VPNMonitor.transition(previous: true, activeInterfaces: Set(names)))
    }

    func testVPNDownEmitsEvent() {
        XCTAssertEqual(VPNMonitor.transition(previous: true, activeInterfaces: []), .down)
    }

    func testVPNStillDownEmitsNothing() {
        XCTAssertNil(VPNMonitor.transition(previous: false, activeInterfaces: []))
    }

    func testPrimeStateWithActiveInterfacesIsUpButSilent() {
        XCTAssertTrue(VPNMonitor.primeState(activeInterfaces: ["utun3"]))
    }

    func testPrimeStateWithNoInterfacesIsDown() {
        XCTAssertFalse(VPNMonitor.primeState(activeInterfaces: []))
    }

    func testInterfaceNamesIgnoresNonUtunKeys() {
        let names = VPNMonitor.interfaceNames(fromKeys: [
            "State:/Network/Interface/en0/IPv4",
            "State:/Network/Interface/utun0/IPv4",
        ])
        XCTAssertEqual(names, ["utun0"])
    }
}
