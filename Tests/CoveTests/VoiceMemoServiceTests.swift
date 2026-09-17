import XCTest
@testable import Cove

@MainActor final class VoiceMemoServiceTests: XCTestCase {
    func testStopWhenIdleIsNoOp() async {
        let voice = VoiceMemoService()
        let url = await voice.stop()
        XCTAssertNil(url)
        XCTAssertFalse(voice.isRecording)
    }
}
