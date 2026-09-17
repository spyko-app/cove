import Foundation

enum CalendarGrid {
    static func leadingBlanks(firstWeekdayOfMonth: Int, firstWeekday: Int) -> Int {
        ((firstWeekdayOfMonth - firstWeekday) + 7) % 7
    }

    static func weekdayLabels(firstWeekday: Int) -> [String] {
        let base = ["D", "S", "T", "Q", "Q", "S", "S"]
        let offset = ((firstWeekday - 1) + 7) % 7
        return (0..<7).map { base[($0 + offset) % 7] }
    }
}
