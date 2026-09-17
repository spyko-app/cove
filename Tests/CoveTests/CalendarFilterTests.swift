import XCTest
@testable import Cove

private struct FakeEvent: CalendarIdentifiable, Equatable {
    let calendarID: String
    let title: String
}

final class CalendarFilterTests: XCTestCase {
    func testSelectedCalendarsFilter() {
        let events = [
            FakeEvent(calendarID: "a", title: "Um"),
            FakeEvent(calendarID: "b", title: "Dois"),
            FakeEvent(calendarID: "c", title: "Três"),
        ]
        let filtered = CalendarService.filter(events: events, selectedIDs: ["a", "c"])
        XCTAssertEqual(filtered.map(\.title), ["Um", "Três"])
    }

    func testEmptySelectionMeansAll() {
        let events = [FakeEvent(calendarID: "a", title: "Um"), FakeEvent(calendarID: "b", title: "Dois")]
        let filtered = CalendarService.filter(events: events, selectedIDs: [])
        XCTAssertEqual(filtered, events)
    }
}
