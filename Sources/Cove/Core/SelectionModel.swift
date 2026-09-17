/// Modelo puro de seleção múltipla (clique/cmd/shift), sem UIKit/AppKit.
/// Usado pela cesta (`ShelfPage`) e pelo clipboard (`ClipboardPage`).
struct SelectionModel<ID: Hashable> {
    private(set) var selected: Set<ID> = []
    var anchor: ID?

    init() {}

    /// Aplica um clique em `id`, dado o modelo `ordered` visível no momento.
    /// - clique simples: seleciona só `id`, vira âncora.
    /// - cmd: alterna `id` na seleção; vira âncora se ficou selecionado.
    /// - shift: seleciona o intervalo [âncora, id] em `ordered` (substitui a seleção); sem âncora, vira clique simples.
    mutating func click(_ id: ID, ordered: [ID], shift: Bool, command: Bool) {
        if shift, let anchor, let from = ordered.firstIndex(of: anchor), let to = ordered.firstIndex(of: id) {
            let range = from <= to ? from...to : to...from
            selected = Set(ordered[range])
            return
        }
        if command {
            if selected.contains(id) {
                selected.remove(id)
            } else {
                selected.insert(id)
                anchor = id
            }
            return
        }
        selected = [id]
        anchor = id
    }

    mutating func clear() {
        selected.removeAll()
        anchor = nil
    }

    /// Reduz a seleção a exatamente `id` e o torna âncora (semântica de clique simples,
    /// sem depender de `ordered`). Usado pela navegação por teclado.
    mutating func selectOnly(_ id: ID) {
        selected = [id]
        anchor = id
    }

    func isSelected(_ id: ID) -> Bool { selected.contains(id) }
}
