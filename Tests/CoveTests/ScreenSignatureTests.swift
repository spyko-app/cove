import XCTest
@testable import Cove

final class ScreenSignatureTests: XCTestCase {
    func testUnchangedScreensSameSignature() {
        let a: [(id: UInt32, frame: CGRect, notch: CGRect?)] = [
            (id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), notch: CGRect(x: 850, y: 1040, width: 220, height: 32)),
        ]
        let b: [(id: UInt32, frame: CGRect, notch: CGRect?)] = [
            (id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), notch: CGRect(x: 850, y: 1040, width: 220, height: 32)),
        ]
        XCTAssertEqual(ScreenSignature.make(a), ScreenSignature.make(b))
    }

    func testDifferentFrameChangesSignature() {
        let a: [(id: UInt32, frame: CGRect, notch: CGRect?)] = [
            (id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), notch: nil),
        ]
        let b: [(id: UInt32, frame: CGRect, notch: CGRect?)] = [
            (id: 1, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), notch: nil),
        ]
        XCTAssertNotEqual(ScreenSignature.make(a), ScreenSignature.make(b))
    }

    func testDifferentScreenSetChangesSignature() {
        let a: [(id: UInt32, frame: CGRect, notch: CGRect?)] = [
            (id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), notch: nil),
        ]
        let b: [(id: UInt32, frame: CGRect, notch: CGRect?)] = [
            (id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), notch: nil),
            (id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), notch: nil),
        ]
        XCTAssertNotEqual(ScreenSignature.make(a), ScreenSignature.make(b))
    }
}
