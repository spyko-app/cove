import Foundation

/// Normalização pura da Cesta (widgets arranjáveis + Quick Actions).
/// Sem estado, sem I/O — testável direto.
enum ShelfLayout {
    /// Ids de widget conhecidos, na ordem canônica de fallback.
    static let knownWidgets: Set<String> = ["files", "quickActions", "recent"]
    /// Ações de drop conhecidas, na ordem canônica de fallback.
    static let knownActions: [String] = ["airdrop", "finder", "compress", "copyPath", "delete", "share"]

    /// Dedupe (mantém a 1ª ocorrência), descarta ids desconhecidos, e garante
    /// "files" presente (a grade é sempre exibida — é a Cesta em si).
    static func normalize(_ ids: [String], known: Set<String> = knownWidgets) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where known.contains(id) && !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        if !result.contains("files") {
            result.insert("files", at: 0)
        }
        return result
    }

    /// Dedupe, descarta desconhecidas, trunca em `limit`; se sobrar menos de 2,
    /// completa com o padrão (na ordem `knownActions`) até o mínimo de 2.
    static func normalizeActions(_ ids: [String], known: [String] = knownActions, limit: Int = 4) -> [String] {
        let knownSet = Set(known)
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where knownSet.contains(id) && !seen.contains(id) {
            seen.insert(id)
            result.append(id)
            if result.count == limit { break }
        }
        if result.count < 2 {
            for fallback in known where !seen.contains(fallback) {
                seen.insert(fallback)
                result.append(fallback)
                if result.count >= 2 { break }
            }
        }
        return result
    }
}
