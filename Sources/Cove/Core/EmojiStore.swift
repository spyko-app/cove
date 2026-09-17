import AppKit

@MainActor
final class EmojiStore: ObservableObject {
    @Published private(set) var recents: [String] = []
    private let storage: URL
    private let limit: Int
    private let pasteboard: NSPasteboard

    init(storage: URL = AppSupport.file("emoji-recents.json"), limit: Int = 24, pasteboard: NSPasteboard = .general) {
        self.storage = storage
        self.limit = limit
        self.pasteboard = pasteboard
        if let data = try? Data(contentsOf: storage),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            recents = saved
        }
    }

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
