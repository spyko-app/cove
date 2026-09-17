import SwiftUI

struct NotesPage: View {
    @ObservedObject var store: NotesStore
    let notchTop: CGFloat

    @State private var query = ""
    @State private var selection: URL?
    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var showReloadButton = false
    @FocusState private var editorFocused: Bool

    private var filtered: [NoteFile] {
        guard !query.isEmpty else { return store.notes }
        return store.notes.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: notchTop)
            toolbar
            HStack(spacing: 8) {
                list.frame(width: 130)
                editor
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onAppear { selectFirstIfNeeded() }
        .onDisappear { flushSave() }
        .onChange(of: store.externalChangeTick) { _, _ in handleExternalChange() }
    }

    private func handleExternalChange() {
        guard let url = selection, store.wasModifiedExternally(url) else { return }
        if saveTask == nil {
            text = store.load(url)
            showReloadButton = false
        } else {
            showReloadButton = true
        }
    }

    private func reloadFromDisk() {
        guard let url = selection else { return }
        saveTask?.cancel()
        saveTask = nil
        text = store.load(url)
        showReloadButton = false
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { createNote() } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))

            if store.isVault {
                Button { openInObsidian() } label: {
                    Image(systemName: "arrow.up.forward.square").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                .disabled(selection == nil)
            }

            Button { deleteSelected() } label: {
                Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
            .disabled(selection == nil)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private var list: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                TextField("Buscar…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.white)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.08)))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { note in
                        noteRow(note)
                    }
                }
            }
        }
    }

    private func noteRow(_ note: NoteFile) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(note.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
            let preview = NoteFileName.firstLine(store.load(note.id))
            Text(preview.isEmpty ? note.modified.formatted(.relative(presentation: .named)) : preview)
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(selection == note.id ? .white.opacity(0.14) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { selectNote(note.id) }
    }

    private var editor: some View {
        Group {
            if selection != nil {
                VStack(spacing: 0) {
                    if showReloadButton {
                        Button { reloadFromDisk() } label: {
                            Label("Alterado fora — recarregar", systemImage: "arrow.clockwise")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.yellow)
                        .padding(.bottom, 6)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(.white)
                        .focused($editorFocused)
                        .onChange(of: text) { _, _ in scheduleAutosave() }
                }
            } else {
                VStack {
                    Spacer()
                    Text("Sem nota selecionada").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
    }

    private func selectFirstIfNeeded() {
        if selection == nil, let first = store.notes.first { selectNote(first.id) }
    }

    private func selectNote(_ url: URL) {
        flushSave()
        selection = url
        text = store.load(url)
        showReloadButton = false
    }

    private func createNote() {
        let url = store.create(title: "Nota")
        selectNote(url)
    }

    private func deleteSelected() {
        guard let url = selection else { return }
        saveTask?.cancel()
        store.delete(url)
        selection = store.notes.first?.id
        text = selection.map(store.load) ?? ""
    }

    private func openInObsidian() {
        guard let url = selection, store.isVault else { return }
        ObsidianQuickNote.open(vault: store.root, note: url)
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        let url = selection
        let content = text
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let url else { return }
            store.save(url, text: content)
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        if let url = selection {
            store.save(url, text: text)
        }
    }
}
