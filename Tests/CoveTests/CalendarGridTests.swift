import XCTest
@testable import Cove

final class CalendarGridTests: XCTestCase {
    func testWeekGridLeadingBlanksSundayStart() {
        // Mês começa numa quarta (weekday 4) — domingo (1) é o início da semana.
        XCTAssertEqual(CalendarGrid.leadingBlanks(firstWeekdayOfMonth: 4, firstWeekday: 1), 3)
    }

    func testWeekGridLeadingBlanksMondayStart() {
        // Mesmo mês, mas semana começa na segunda (2): quarta é a 3ª coluna (0-based 2).
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
