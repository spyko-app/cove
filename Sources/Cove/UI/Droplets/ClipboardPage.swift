import SwiftUI

private extension Color {
    /// `#RGB`/`#RRGGBB`/`#RRGGBBAA` já normalizado (vem de `ClipboardStore.hexColor`).
    init?(hex: String) {
        var hex = hex; if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let r, g, b, a: UInt64
        if hasAlpha { r = (value >> 24) & 0xFF; g = (value >> 16) & 0xFF; b = (value >> 8) & 0xFF; a = value & 0xFF }
        else { r = (value >> 16) & 0xFF; g = (value >> 8) & 0xFF; b = value & 0xFF; a = 255 }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

struct ClipboardPage: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var linkPreviews: LinkPreviewCache
    var coordinator: NotchCoordinator?
    let notchTop: CGFloat
    @State private var query = ""
    @State private var copiedID: UUID?
    @State private var selectedID: UUID?
    @State private var selection = SelectionModel<UUID>()
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @FocusState private var searchFocused: Bool
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: notchTop)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                TextField("Buscar…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                    .focused($searchFocused)
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.08)))
            .padding(.horizontal, 16)

            header

            if store.search(query).isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 22)).foregroundStyle(.white.opacity(0.5))
                    Text(query.isEmpty ? "Sem histórico ainda" : "Nada encontrado").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        let results = store.search(query)
                        let pinned = results.filter(\.pinned)
                        let rest = results.filter { !$0.pinned }
                        if !pinned.isEmpty {
                            Text("Fixados")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(pinned) { e in row(e) }
                        }
                        ForEach(rest) { e in row(e) }
                    }
                    .padding(.horizontal, 12)
                }
                HStack {
                    Spacer()
                    Button("Limpar histórico") { store.clear() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 18).padding(.bottom, 8)
            }
        }
        .onKeyPress(.downArrow) { guard renamingID == nil else { return .ignored }; moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { guard renamingID == nil else { return .ignored }; moveSelection(-1); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            handleReturn(collapse: press.modifiers.contains(.command))
        }
        .onKeyPress("r") {
            guard renamingID == nil, !searchFocused else { return .ignored }
            startRename()
            return renamingID == nil ? .ignored : .handled
        }
        .onKeyPress(.delete) {
            guard renamingID == nil, !searchFocused else { return .ignored }
            deleteSelected(); return .handled
        }
        .onKeyPress(.deleteForward) {
            guard renamingID == nil, !searchFocused else { return .ignored }
            deleteSelected(); return .handled
        }
        .onKeyPress("c", phases: .down) { press in
            guard renamingID == nil, !searchFocused, press.modifiers.contains(.command) else { return .ignored }
            copySelected(); return .handled
        }
        .onKeyPress(.escape) {
            guard renamingID == nil else { return .ignored }
            guard !selection.selected.isEmpty else { return .ignored }
            selection.clear(); return .handled
        }
        .onAppear {
            NotchPanelController.current?.makeKey()
            if selectedID == nil { selectedID = store.search(query).first?.id }
            searchFocused = true
        }
        .onDisappear { NotchPanelController.current?.resignKey() }
    }

    private var header: some View {
        let total = store.search("").count
        let fixed = store.search("").filter(\.pinned).count
        return Text("\(total) itens · \(fixed) fixados")
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
    }

    private func visibleResults() -> [ClipEntry] {
        let results = store.search(query)
        return results.filter(\.pinned) + results.filter { !$0.pinned }
    }

    private func moveSelection(_ delta: Int) {
        let list = visibleResults()
        guard !list.isEmpty else { return }
        guard let current = selectedID, let i = list.firstIndex(where: { $0.id == current }) else {
            let id = delta > 0 ? list.first?.id : list.last?.id
            selectedID = id
            if let id { selection.selectOnly(id) }
            return
        }
        let next = min(max(i + delta, 0), list.count - 1)
        let id = list[next].id
        selectedID = id
        selection.selectOnly(id)
    }

    @discardableResult
    private func handleReturn(collapse: Bool) -> KeyPress.Result {
        if let renamingID {
            commitRename(renamingID)
            return .handled
        }
        guard let id = selectedID, let e = visibleResults().first(where: { $0.id == id }) else { return .ignored }
        performCopy(e)
        if collapse { coordinator?.requestExpand(false) }
        return .handled
    }

    private func startRename() {
        guard renamingID == nil, let id = selectedID, let e = visibleResults().first(where: { $0.id == id }) else { return }
        renamingID = id
        renameText = e.label ?? ""
        Task { @MainActor in
            renameFocused = true
        }
    }

    private func commitRename(_ id: UUID) {
        store.rename(id, label: renameText)
        renamingID = nil
        renameText = ""
        renameFocused = false
        searchFocused = true
    }

    private func cancelRename() {
        renamingID = nil
        renameText = ""
        renameFocused = false
        searchFocused = true
    }

    /// ids-alvo pra ações de seleção múltipla: usa `selection.selected` se não-vazio, senão o foco (`selectedID`).
    private func targetIDs() -> Set<UUID> {
        if !selection.selected.isEmpty { return selection.selected }
        if let id = selectedID { return [id] }
        return []
    }

    private func deleteSelected() {
        let ids = targetIDs()
        guard !ids.isEmpty else { return }
        let list = visibleResults()
        let i = list.firstIndex { ids.contains($0.id) } ?? 0
        for id in ids { store.remove(id) }
        selection.clear()
        let remaining = visibleResults()
        selectedID = remaining.isEmpty ? nil : remaining[min(i, remaining.count - 1)].id
    }

    /// ⌘C: copia a seleção múltipla — texto (junta com `\n`) ou arquivos (`writeObjects`).
    /// Um único item selecionado cai no `performCopy` normal (mantém o feedback "Copiado").
    private func copySelected() {
        let ids = targetIDs()
        guard ids.count > 1 else {
            if let id = ids.first, let e = visibleResults().first(where: { $0.id == id }) { performCopy(e) }
            return
        }
        let entries = visibleResults().filter { ids.contains($0.id) }
        guard !entries.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        if entries.allSatisfy({ $0.kind == .file }) {
            let urls = entries.map { URL(fileURLWithPath: $0.text) }
            pb.writeObjects(urls as [NSURL])
        } else {
            pb.setString(entries.map(\.text).joined(separator: "\n"), forType: .string)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func rowBackground(for e: ClipEntry) -> Color {
        if selection.isSelected(e.id) { return .white.opacity(0.18) }
        if selectedID == e.id { return .white.opacity(0.12) }
        return .white.opacity(0.06)
    }

    private func performCopy(_ e: ClipEntry) {
        store.copy(e)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        copiedID = e.id
        Task {
            try? await Task.sleep(for: .seconds(1))
            if copiedID == e.id { copiedID = nil }
        }
    }

    private func row(_ e: ClipEntry) -> some View {
        Button {
            let flags = NSEvent.modifierFlags
            if flags.contains(.shift) || flags.contains(.command) {
                selection.click(e.id, ordered: visibleResults().map(\.id), shift: flags.contains(.shift), command: flags.contains(.command))
                selectedID = e.id
            } else {
                selection.clear()
                selectedID = e.id
                performCopy(e)
            }
        } label: {
            HStack(spacing: 8) {
                if e.kind == .image, let path = e.thumbnailPath, let img = NSImage(contentsOfFile: path) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 20).clipShape(RoundedRectangle(cornerRadius: 3))
                } else if e.kind == .url, let url = URL(string: e.text), copiedID != e.id {
                    linkIcon(for: url)
                } else {
                    Image(systemName: icon(for: e.kind)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).frame(width: 16)
                }
                if let hex = store.hexColor(in: e.text), let color = Color(hex: hex) {
                    Circle().fill(color).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))
                }
                if renamingID == e.id {
                    TextField("Rótulo", text: $renameText)
                        .textFieldStyle(.plain).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .focused($renameFocused)
                        .onKeyPress(.escape) { cancelRename(); return .handled }
                        .onSubmit { commitRename(e.id) }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        if let label = e.label, !label.isEmpty {
                            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.95)).lineLimit(1)
                        }
                        if e.kind == .url, let url = URL(string: e.text), copiedID != e.id, let preview = linkPreviews.preview(for: url) {
                            Text(preview.title ?? preview.host)
                                .font(.system(size: 12, weight: e.label == nil ? .bold : .regular)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                            Text(preview.host)
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                        } else {
                            Text(copiedID == e.id ? "Copiado" : e.text)
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                        }
                    }
                }
                Spacer()
                if e.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                }
                Text(e.date, style: .time).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(rowBackground(for: e)))
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle())
        .contextMenu {
            let ids = selection.isSelected(e.id) && selection.selected.count > 1 ? selection.selected : [e.id]
            if ids.count == 1 {
                Button(e.pinned ? "Desafixar" : "Fixar") { store.togglePin(e.id) }
                Button("Renomear") { selectedID = e.id; startRename() }
            }
            Button(ids.count > 1 ? "Remover \(ids.count) itens" : "Remover") {
                for id in ids { store.remove(id) }
                selection.clear()
            }
        }
        .task {
            guard e.kind == .url, let url = URL(string: e.text) else { return }
            if linkPreviews.preview(for: url) == nil { linkPreviews.fetch(url) }
        }
    }

    @ViewBuilder
    private func linkIcon(for url: URL) -> some View {
        if let png = linkPreviews.preview(for: url)?.iconPNG, let img = NSImage(data: png) {
            Image(nsImage: img).resizable().frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "link").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).frame(width: 16)
        }
    }

    private func icon(for kind: ClipEntry.Kind) -> String {
        switch kind {
        case .text: "doc.text"
        case .url: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }
}
