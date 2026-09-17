import Foundation

/// Busca pura no catálogo de emoji — sem estado, sem disco (testável isolado).
enum EmojiSearch {
    /// Normaliza pra comparação: minúsculo + sem diacríticos (ex.: "coração" → "coracao").
    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    /// `q` vazio → recentes (na ordem, pelo `char`) seguidos do catálogo agrupado.
    /// `q` não vazio → nome/keywords batendo (case/diacrítico-insensível), recentes primeiro.
    static func matches(_ q: String, in catalog: [Emoji], recents: [String] = []) -> [Emoji] {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let recentEmoji = recents.compactMap { char in catalog.first { $0.char == char } }
            let recentChars = Set(recents)
            let rest = catalog.filter { !recentChars.contains($0.char) }
            return recentEmoji + rest
        }
        let needle = normalize(trimmed)
        let found = catalog.filter { emoji in
            normalize(emoji.name).contains(needle) || emoji.keywords.contains { normalize($0).contains(needle) }
        }
        let recentChars = Set(recents)
        let rankedRecent = found.filter { recentChars.contains($0.char) }
        let rankedRest = found.filter { !recentChars.contains($0.char) }
        return rankedRecent + rankedRest
    }
}
