import XCTest
@testable import Cove

final class CalendarGridTests: XCTestCase {
    func testWeekGridLeadingBlanksSundayStart() {
        XCTAssertEqual(CalendarGrid.leadingBlanks(firstWeekdayOfMonth: 4, firstWeekday: 1), 3)
    }

    func testWeekGridLeadingBlanksMondayStart() {
        XCTAssertEqual(CalendarGrid.leadingBlanks(firstWeekdayOfMonth: 4, firstWeekday: 2), 2)
    }

    func testWeekGridLeadingBlanksNoOffset() {
        XCTAssertEqual(CalendarGrid.leadingBlanks(firstWeekdayOfMonth: 1, firstWeekday: 1), 0)
    }

    func testWeekdayLabelsRotateWithFirstWeekday() {
        XCTAssertEqual(CalendarGrid.weekdayLabels(firstWeekday: 1), ["D", "S", "T", "Q", "Q", "S", "S"])
        XCTAssertEqual(CalendarGrid.weekdayLabels(firstWeekday: 2), ["S", "T", "Q", "Q", "S", "S", "D"])
    }
}
