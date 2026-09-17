import Foundation

struct LyricLine: Equatable {
    let time: Double
    let text: String
}

enum LRCParser {
    static func parse(_ lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for rawLine in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let (times, text) = extractTimestamps(from: line)
            guard !times.isEmpty else { continue }
            for t in times {
                result.append(LyricLine(time: t, text: text))
            }
        }
        return result.sorted { $0.time < $1.time }
    }

    static func currentIndex(_ lines: [LyricLine], at t: Double) -> Int? {
        var found: Int?
        for (i, line) in lines.enumerated() {
            if line.time <= t {
                found = i
            } else {
                break
            }
        }
        return found
    }

    private static func extractTimestamps(from line: String) -> (times: [Double], text: String) {
        var times: [Double] = []
        var rest = Substring(line)
        while rest.hasPrefix("[") {
            guard let closeIdx = rest.firstIndex(of: "]") else { break }
            let tag = rest[rest.index(after: rest.startIndex)..<closeIdx]
            if let time = parseTimeTag(String(tag)) {
                times.append(time)
                rest = rest[rest.index(after: closeIdx)...]
            } else {
                return ([], "")
            }
        }
        return (times, String(rest).trimmingCharacters(in: .whitespaces))
    }

    private static func parseTimeTag(_ tag: String) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1])
        else { return nil }
        return minutes * 60 + seconds
    }
}
