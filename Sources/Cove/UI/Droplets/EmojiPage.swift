import AppKit
import SwiftUI

/// Droplet Emoji — busca por nome/keyword (pt-BR + en), recentes MRU, grade 10
/// colunas. ↩ agora cola no cursor quando a Acessibilidade está confiada
/// (`AXIsProcessTrusted`, via `PasteAtCursor` — T36); ⇧↩ só copia pro pasteboard.
struct EmojiPage: View {
    @ObservedObject var store: EmojiStore
    var coordinator: NotchCoordinator?
    let notchTop: CGFloat
    @State private var query = ""
    @State private var selectedChar: String?
    @FocusState private var searchFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

    private var results: [Emoji] {
        EmojiSearch.matches(query, in: EmojiCatalog.all, recents: store.recents)
    }

    private var grouped: [(String, [Emoji])] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [("", results)] }
        let recentChars = Set(store.recents)
        var out: [(String, [Emoji])] = []
        let recentEmoji = results.filter { recentChars.contains($0.char) }
        if !recentEmoji.isEmpty { out.append(("Recentes", recentEmoji)) }
        var seen = Set<String>()
        for e in results where !recentChars.contains(e.char) {
            if !seen.contains(e.group) {
                seen.insert(e.group)
                out.append((e.group, results.filter { !recentChars.contains($0.char) && $0.group == e.group }))
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: notchTop)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                TextField("Buscar emoji…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.08)))
            .padding(.horizontal, 16)

            if results.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "face.smiling").font(.system(size: 22)).foregroundStyle(.white.opacity(0.5))
                    Text("Nada encontrado").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(grouped, id: \.0) { group, items in
                            if !group.isEmpty {
                                Text(group)
                                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                            }
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(items) { e in cell(e) }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }

            if AXIsProcessTrusted() {
                Text("↩ cola no cursor · ⇧↩ copia")
                    .font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 4)
            }
        }
        .onKeyPress(.leftArrow) { guard !searchFocused else { return .ignored }; moveSelection(-1); return .handled }
        .onKeyPress(.rightArrow) { guard !searchFocused else { return .ignored }; moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(-10); return .handled }
        .onKeyPress(.downArrow) { moveSelection(10); return .handled }
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard let char = selectedChar else { return .ignored }
            use(char, pasteAtCursor: !press.modifiers.contains(.shift))
            return .handled
        }
        .onAppear {
            NotchPanelController.current?.makeKey()
            if selectedChar == nil { selectedChar = results.first?.char }
            searchFocused = true
        }
        .onDisappear { NotchPanelController.current?.resignKey() }
    }

    private func moveSelection(_ delta: Int) {
        let list = results
        guard !list.isEmpty else { return }
        guard let current = selectedChar, let i = list.firstIndex(where: { $0.char == current }) else {
            selectedChar = delta > 0 ? list.first?.char : list.last?.char
            return
        }
        let next = min(max(i + delta, 0), list.count - 1)
        selectedChar = list[next].char
    }

    private func use(_ char: String, pasteAtCursor: Bool = false) {
        let pasted = store.use(char, pasteAtCursor: pasteAtCursor)
        coordinator?.notify(app: "Emoji", title: pasted ? "\(char) colado" : "\(char) copiado")
    }

    private func cell(_ e: Emoji) -> some View {
        Button {
            selectedChar = e.char
            use(e.char, pasteAtCursor: true)
        } label: {
            Text(e.char)
                .font(.system(size: 22))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(selectedChar == e.char ? 0.18 : 0.001)))
        }
        .buttonStyle(.plain)
        .help(e.name)
    }
}
