import Foundation

/// Cálculo puro da grade do mês do `CalendarWidget` — sem SwiftUI, testável direto.
enum CalendarGrid {
    /// Quantas células vazias vêm antes do dia 1 numa grade de 7 colunas,
    /// dado o weekday (1=domingo…7=sábado) do primeiro dia do mês e o
    /// weekday configurado como início da semana (`NotchConfig.firstWeekday`).
    static func leadingBlanks(firstWeekdayOfMonth: Int, firstWeekday: Int) -> Int {
        ((firstWeekdayOfMonth - firstWeekday) + 7) % 7
    }

    /// Rótulos das colunas (D/S/T/Q/Q/S/S) já rotacionados a partir do início da semana.
    static func weekdayLabels(firstWeekday: Int) -> [String] {
        let base = ["D", "S", "T", "Q", "Q", "S", "S"]
        let offset = ((firstWeekday - 1) + 7) % 7
        return (0..<7).map { base[($0 + offset) % 7] }
    }
}
