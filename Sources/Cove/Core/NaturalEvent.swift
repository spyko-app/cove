import Foundation

enum NaturalEvent {
    enum Kind: Equatable { case event, reminder }
    struct Draft: Equatable { var title: String; var start: Date; var end: Date; var kind: Kind = .event }

    private static let reminderPrefixes = [
        "me lembra de ", "me lembra ", "lembrete de ", "lembrete ", "lembrar de ", "lembrar ",
    ]

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Draft? {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        var text = text
        var kind: Kind = .event
        let lower = text.lowercased()
        for prefix in reminderPrefixes where lower.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            kind = .reminder
            break
        }
        let ns = text as NSString
        guard let m = det.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), let date = m.date else { return nil }
        var title = ns.replacingCharacters(in: m.range, with: "")
        for filler in ["às", "as", "em", "no", "na", "de", "para", "pra"] {
            title = title.replacingOccurrences(of: " \(filler) ", with: " ")
            if title.lowercased().hasSuffix(" \(filler)") { title = String(title.dropLast(filler.count + 1)) }
            if title.lowercased().hasPrefix("\(filler) ") { title = String(title.dropFirst(filler.count + 1)) }
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if title.isEmpty { title = "Evento" }
        let end = date.addingTimeInterval(m.duration > 0 ? m.duration : 3600)
        return Draft(title: title, start: date, end: end, kind: kind)
    }
}
