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

    static func selectionMove(count: Int, index: Int, delta: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }

    static func shouldPreviewOnSpace(fieldFocused: Bool, hasSelection: Bool) -> Bool {
        !fieldFocused && hasSelection
    }
}
