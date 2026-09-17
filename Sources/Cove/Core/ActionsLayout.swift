import Foundation

/// Layout puro da grade de Ações rápidas (ex-Ring): 1–4 fatias cabem numa
/// linha só, 5–8 sempre viram 4 colunas (2 linhas) — nunca mais largo que isso.
enum ActionsGrid {
    static func columns(for count: Int) -> Int {
        count <= 4 ? max(count, 1) : 4
    }
}
