import XCTest
@testable import Cove

@MainActor final class ScreenCaptureTests: XCTestCase {
    private let out = URL(fileURLWithPath: "/tmp/Captura teste.png")

    func testArgumentsPerMode() {
        XCTAssertEqual(ScreenCapture.arguments(for: .region, output: out), ["-i", "-x", out.path])
        XCTAssertEqual(ScreenCapture.arguments(for: .window, output: out), ["-i", "-W", "-x", out.path])
        XCTAssertEqual(ScreenCapture.arguments(for: .fullScreen, output: out), ["-x", out.path])
        XCTAssertEqual(ScreenCapture.arguments(for: .timer(seconds: 5), output: out), ["-T", "5", "-x", out.path])
    }

    func testTimerSecondsClamped() {
        XCTAssertEqual(ScreenCapture.arguments(for: .timer(seconds: 0), output: out), ["-T", "1", "-x", out.path])
        XCTAssertEqual(ScreenCapture.arguments(for: .timer(seconds: -10), output: out), ["-T", "1", "-x", out.path])
        XCTAssertEqual(ScreenCapture.arguments(for: .timer(seconds: 120), output: out), ["-T", "60", "-x", out.path])
        XCTAssertEqual(ScreenCapture.arguments(for: .timer(seconds: 60), output: out), ["-T", "60", "-x", out.path])
    }

    func testOutputsIncludeDisplaySuffixes() {
        let base = URL(fileURLWithPath: "/tmp/captures/Captura teste.png")
        let base1 = URL(fileURLWithPath: "/tmp/captures/Captura teste-1.png")
        let unrelated = URL(fileURLWithPath: "/tmp/captures/Outra coisa.png")
        let older = URL(fileURLWithPath: "/tmp/captures/Captura teste-2.png")
        let since = Date()
        let mtimes: [URL: Date] = [
            base: since.addingTimeInterval(1),
            base1: since.addingTimeInterval(1),
            unrelated: since.addingTimeInterval(1),
            older: since.addingTimeInterval(-10),
        ]
        let result = ScreenCapture.outputs(
            base: base,
            candidates: [base, base1, unrelated, older],
            since: since,
            mtimes: mtimes
        )
        XCTAssertEqual(result, [base, base1])
    }
}
