/// Ações puras do menu "···" de cada resultado da busca (sem AppKit) —
/// atalhos exibidos no título do item e clamp de seleção por teclado.
enum SearchActions {
    enum Action: CaseIterable {
        case open, reveal, quickLook, copyPath, sendToShelf
    }

    static func shortcutHint(for action: Action) -> String {
        switch action {
        case .open: "Abrir ⏎"
        case .reveal: "Revelar no Finder ⌘R"
        case .quickLook: "Quick Look ␣"
        case .copyPath: "Copiar caminho ⌘C"
        case .sendToShelf: "Enviar pra Cesta ⌘S"
        }
    }

    /// Move `index` por `delta` dentro de `[0, count)`, sem estourar os limites.
    static func selectionMove(count: Int, index: Int, delta: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }

    /// Espaço só dispara Quick Look quando o campo de busca NÃO está com foco —
    /// senão intercepta o espaço enquanto o usuário digita o termo da busca.
    static func shouldPreviewOnSpace(fieldFocused: Bool, hasSelection: Bool) -> Bool {
        !fieldFocused && hasSelection
    }
}
