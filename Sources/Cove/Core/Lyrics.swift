import Foundation

/// Uma linha de letra sincronizada (LRC).
struct LyricLine: Equatable {
    let time: Double
    let text: String
}

/// Parser puro de arquivos LRC (`.lrc`). Sem I/O, sem dependências externas.
enum LRCParser {
    /// Extrai as linhas de um LRC, ignorando tags de metadado (`[ar:]`, `[ti:]`, etc.)
    /// e suportando múltiplos timestamps por linha e milissegundos com 2 ou 3 dígitos.
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

    /// Retorna o índice da última linha cujo `time` é <= t, ou nil se nenhuma linha
    /// ainda começou (ou o array está vazio).
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

    /// Extrai todos os timestamps `[mm:ss.xx]`/`[mm:ss.xxx]` no início da linha
    /// (podem se repetir) e devolve o texto restante. Tags de metadado (letras
    /// não-numéricas logo após `[`, ex.: `[ar:Artista]`) são ignoradas.
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
                // não é um timestamp (é metadado tipo [ar:...]) — a linha inteira é ignorada
                return ([], "")
            }
        }
        return (times, String(rest).trimmingCharacters(in: .whitespaces))
    }

    /// `mm:ss.xx` ou `mm:ss.xxx` → segundos totais. nil se não bater o formato.
    private static func parseTimeTag(_ tag: String) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1])
        else { return nil }
        return minutes * 60 + seconds
    }
}
