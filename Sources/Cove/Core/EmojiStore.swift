import AppKit

/// Recentes do droplet Emoji — MRU, persistido em `AppSupport/emoji-recents.json`.
/// `use(_:)` copia pro pasteboard (colar-no-cursor exige Acessibilidade → T36).
@MainActor
final class EmojiStore: ObservableObject {
    @Published private(set) var recents: [String] = []
    private let storage: URL
    private let limit: Int
    private let pasteboard: NSPasteboard

    /// `pasteboard` injetável — testes usam um `NSPasteboard` nomeado próprio
    /// pra não sujar o clipboard real da máquina que roda a suíte.
    init(storage: URL = AppSupport.file("emoji-recents.json"), limit: Int = 24, pasteboard: NSPasteboard = .general) {
        self.storage = storage
        self.limit = limit
        self.pasteboard = pasteboard
        if let data = try? Data(contentsOf: storage),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            recents = saved
        }
    }

    /// `pasteAtCursor: true` tenta colar direto (T36); se falhar (sem
    /// Acessibilidade, ou nada pra colar), cai em só copiar pro pasteboard.
    @discardableResult
    func use(_ char: String, pasteAtCursor: Bool = false) -> Bool {
        let pasted = pasteAtCursor && PasteAtCursor.paste(char)
        if !pasted {
            pasteboard.clearContents()
            pasteboard.setString(char, forType: .string)
        }
        recents.removeAll { $0 == char }
        recents.insert(char, at: 0)
        if recents.count > limit { recents = Array(recents.prefix(limit)) }
        save()
        return pasted
    }

    private func save() {
        try? JSONEncoder().encode(recents).write(to: storage)
    }
}
