import XCTest
@testable import Cove

final class MotionMathTests: XCTestCase {

    // MARK: - smooth

    func testSmoothAlphaOneUsesNext() {
        let result = MotionMath.smooth(prev: [0, 0, 0], next: [0.4, 0.8, 1], alpha: 1)
        XCTAssertEqual(result, [0.4, 0.8, 1])
    }

    func testSmoothAlphaZeroKeepsPrev() {
        let result = MotionMath.smooth(prev: [0.2, 0.5, 0.9], next: [0.4, 0.8, 1], alpha: 0)
        XCTAssertEqual(result, [0.2, 0.5, 0.9])
    }

    func testSmoothInterpolatesBetween() {
        let result = MotionMath.smooth(prev: [0], next: [1], alpha: 0.5)
        XCTAssertEqual(result, [0.5])
    }

    func testSmoothClampsAlphaOutOfRange() {
        let over = MotionMath.smooth(prev: [0], next: [1], alpha: 2)
        XCTAssertEqual(over, [1])
        let under = MotionMath.smooth(prev: [0.3], next: [1], alpha: -1)
        XCTAssertEqual(under, [0.3])
    }

    func testSmoothFallsBackToNextWhenPrevShorter() {
        let result = MotionMath.smooth(prev: [], next: [0.6, 0.7], alpha: 0.3)
        XCTAssertEqual(result, [0.6, 0.7])
    }

    // MARK: - energy

    func testEnergyMean() {
        XCTAssertEqual(MotionMath.energy([0, 0.5, 1]), 0.5, accuracy: 0.0001)
    }

    func testEnergyClampedToZeroOne() {
        XCTAssertEqual(MotionMath.energy([2, 2]), 1)
        XCTAssertEqual(MotionMath.energy([-1, -1]), 0)
    }

    func testEnergyEmptyIsZero() {
        XCTAssertEqual(MotionMath.energy([]), 0)
    }
}
