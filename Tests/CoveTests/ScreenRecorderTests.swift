import XCTest
@testable import Cove

@MainActor final class ScreenRecorderTests: XCTestCase {
    func testElapsedFormatting() {
        XCTAssertEqual(ScreenRecorder.formatElapsed(0), "00:00")
        XCTAssertEqual(ScreenRecorder.formatElapsed(9), "00:09")
        XCTAssertEqual(ScreenRecorder.formatElapsed(65), "01:05")
        XCTAssertEqual(ScreenRecorder.formatElapsed(3661), "61:01")
    }

    func testOutputURLIsInRecordingsDir() {
        let url = ScreenRecorder.outputURL(stamp: "2026-09-09 20.00.00")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "recordings")
        XCTAssertEqual(url.lastPathComponent, "Gravação 2026-09-09 20.00.00.mp4")
        XCTAssertEqual(url.pathExtension, "mp4")
    }

    func testStopWhenIdleIsNoOp() async {
        let recorder = ScreenRecorder()
        let url = await recorder.stop()
        XCTAssertNil(url)
        XCTAssertFalse(recorder.isRecording)
    }

    func testValidRecordingFile() {
        XCTAssertTrue(ScreenRecorder.isValidRecording(sizeBytes: 1024, exists: true))
        XCTAssertFalse(ScreenRecorder.isValidRecording(sizeBytes: 0, exists: true))
        XCTAssertFalse(ScreenRecorder.isValidRecording(sizeBytes: nil, exists: true))
        XCTAssertFalse(ScreenRecorder.isValidRecording(sizeBytes: 1024, exists: false))
    }
}
