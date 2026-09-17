import XCTest
@testable import Cove

final class PermissionStateTests: XCTestCase {
    func testSummaryAllGranted() {
        let states = ["a": true, "b": true]
        XCTAssertEqual(PermissionState.summary(states), "2 de 2 concedidas")
    }

    func testSummaryNoneGranted() {
        let states = ["a": false, "b": false, "c": false]
        XCTAssertEqual(PermissionState.summary(states), "0 de 3 concedidas")
    }

    func testSummaryPartial() {
        let states = ["a": true, "b": false, "c": true, "d": false, "e": true, "f": false]
        XCTAssertEqual(PermissionState.summary(states), "3 de 6 concedidas")
    }

    func testSummaryEmpty() {
        XCTAssertEqual(PermissionState.summary([:]), "0 de 0 concedidas")
    }
}
