import XCTest
@testable import Cove

final class DeviceSymbolTests: XCTestCase {
    func testSpeakerIsNotAirpods() {
        XCTAssertEqual(DeviceSymbol.symbol(for: "JBL Flip 5", connected: true), "hifispeaker.fill")
    }
    func testAirpodsFamilies() {
        XCTAssertEqual(DeviceSymbol.symbol(for: "AirPods Pro do Mateus", connected: true), "airpods.pro")
        XCTAssertEqual(DeviceSymbol.symbol(for: "AirPods Max", connected: false), "airpods.max")
        XCTAssertEqual(DeviceSymbol.symbol(for: "AirPods", connected: true), "airpods")
    }
    func testOtherKinds() {
        XCTAssertEqual(DeviceSymbol.symbol(for: "Magic Keyboard", connected: true), "keyboard")
        XCTAssertEqual(DeviceSymbol.symbol(for: "WH-1000XM5", connected: true), "headphones")
        XCTAssertEqual(DeviceSymbol.symbol(for: "Coisa Desconhecida", connected: true), "dot.radiowaves.left.and.right")
    }
}
