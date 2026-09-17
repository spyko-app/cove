import SwiftUI

struct SearchPage: View {
    @ObservedObject var coordinator: NotchCoordinator
    let notchTop: CGFloat
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool

    private var spotlight: SpotlightSearch { coordinator.spotlight }
    private var eventDraft: NaturalEvent.Draft? { NaturalEvent.parse(query) }

    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: notchTop)
            HStack(spacing: 6) {
                ZStack {
                    switch SearchIndicator.resolve(isSearching: spotlight.isSearching) {
                    case .orb: SearchOrb()
                    case .glass:
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: SearchOrb.size, height: SearchOrb.size)
                TextField("Buscar ou perguntar", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                    .focused($focused)
                    .onChange(of: query) { spotlight.search(query); selectedIndex = 0; focused = true }
                    .onKeyPress(.downArrow) { moveSelection(1); focused = false; return .handled }
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                    .onKeyPress(.escape) { focused = true; return .handled }
                    .onSubmit {
                        if NSEvent.modifierFlags.contains(.command) {
                            if let r = spotlight.results.first { reveal(r) }
                        } else if let d = eventDraft {
                            createEvent(d)
                        } else {
                            open(spotlight.results.first)
                        }
                    }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.08)))
            .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(spacing: 4) {
                    Section {
                        if let d = eventDraft {
                            Button {
                                createEvent(d)
                            } label: {
                                Label(
                                    "\(d.kind == .reminder ? "Criar lembrete" : "Criar evento"): \(d.title) · \(d.start.formatted(.dateTime.day().month().hour().minute()))",
                                    systemImage: d.kind == .reminder ? "bell.badge.fill" : "calendar.badge.plus"
                                )
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(NotchButtonStyle())
                        }
                    }
                    Section {
                        if !coordinator.config.obsidianVaultPath.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                createNote(query)
                            } label: {
                                Label("Nota Obsidian: \(query)", systemImage: "note.text.badge.plus")
                                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(NotchButtonStyle())
                        }
                    }
                    Section {
                        if query.isEmpty {
                            EmptyView()
                        } else if spotlight.results.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(.white.opacity(0.5))
                                Text("Nada encontrado").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                        } else {
                            ForEach(Array(spotlight.results.enumerated()), id: \.element.id) { i, r in row(r, index: i) }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .onKeyPress(" ", phases: .down) { _ in
            guard let r = selectedResult, SearchActions.shouldPreviewOnSpace(fieldFocused: focused, hasSelection: true) else {
                return .ignored
            }
            quickLook(r); return .handled
        }
        .onKeyPress("c", phases: .down) { press in
            guard press.modifiers.contains(.command), let r = selectedResult else { return .ignored }
            copyPath(r); return .handled
        }
        .onKeyPress("s", phases: .down) { press in
            guard press.modifiers.contains(.command), let r = selectedResult else { return .ignored }
            sendToShelf(r); return .handled
        }
        .onKeyPress("r", phases: .down) { press in
            guard press.modifiers.contains(.command), let r = selectedResult else { return .ignored }
            reveal(r); return .handled
        }
        .onAppear {
            NotchPanelController.current?.makeKey()
            focused = true
        }
        .onDisappear {
            spotlight.cancel()
            QuickLookController.shared.dismiss()
            NotchPanelController.current?.resignKey()
        }
        .onChange(of: coordinator.isExpanded) { _, expanded in
            if !expanded { QuickLookController.shared.dismiss() }
        }
    }

    private var selectedResult: SpotlightSearch.Result? {
        guard spotlight.results.indices.contains(selectedIndex) else { return nil }
        return spotlight.results[selectedIndex]
    }

    private func moveSelection(_ delta: Int) {
        selectedIndex = SearchActions.selectionMove(count: spotlight.results.count, index: selectedIndex, delta: delta)
    }

    private func row(_ r: SpotlightSearch.Result, index: Int) -> some View {
        ResultRow(
            result: r,
            selected: index == selectedIndex,
            onOpen: {
                selectedIndex = index
                if NSEvent.modifierFlags.contains(.command) { reveal(r) } else { open(r) }
            },
            onQuickLook: { quickLook(r) },
            actionButtons: { actionButtons(for: r) }
        )
    }

    @ViewBuilder
    private func actionButtons(for r: SpotlightSearch.Result) -> some View {
        Button(SearchActions.shortcutHint(for: .open)) { open(r) }
        Button(SearchActions.shortcutHint(for: .reveal)) { reveal(r) }
        Button(SearchActions.shortcutHint(for: .quickLook)) { quickLook(r) }
        Button(SearchActions.shortcutHint(for: .copyPath)) { copyPath(r) }
        Button(SearchActions.shortcutHint(for: .sendToShelf)) { sendToShelf(r) }
    }

    private func open(_ r: SpotlightSearch.Result?) {
        guard let r else { return }
        NSWorkspace.shared.open(r.id)
    }

    private func reveal(_ r: SpotlightSearch.Result) {
        NSWorkspace.shared.activateFileViewerSelecting([r.id])
    }

    private func quickLook(_ r: SpotlightSearch.Result) {
        QuickLookController.shared.preview(r.id)
    }

    private func copyPath(_ r: SpotlightSearch.Result) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([r.id as NSURL])
        pb.setString(r.id.path, forType: .string)
        coordinator.notify(app: "Busca", title: "Caminho copiado")
    }

    private func sendToShelf(_ r: SpotlightSearch.Result) {
        coordinator.shelf.add([r.id])
        coordinator.notify(app: "Busca", title: "Enviado pra Cesta")
    }

    private func createEvent(_ d: NaturalEvent.Draft) {
        let minutes = max(0, Int(d.start.timeIntervalSinceNow / 60))
        Task {
            do {
                if d.kind == .reminder {
                    try await coordinator.calendar.createReminder(d)
                    coordinator.notify(app: "Lembretes", title: "Lembrete criado: \(d.title)")
                } else {
                    try await coordinator.calendar.create(d)
                    coordinator.announceEvent(title: d.title, minutes: minutes)
                }
            } catch CalendarService.CreateError.accessDenied {
                let app = d.kind == .reminder ? "Lembretes" : "Calendário"
                coordinator.notify(app: app, title: "Permita o acesso em Privacidade")
            } catch {
                let what = d.kind == .reminder ? "o lembrete" : "o evento"
                coordinator.notify(app: "Calendário", title: "Não foi possível criar \(what)")
            }
        }
        NotchPanelController.current?.resignKey()
    }

    private func createNote(_ text: String) {
        guard !coordinator.config.obsidianVaultPath.isEmpty else { return }
        let vault = URL(fileURLWithPath: coordinator.config.obsidianVaultPath)
        do {
            _ = try ObsidianQuickNote.append(text, vault: vault)
            coordinator.notify(app: "Obsidian", title: "Anotado")
        } catch {
            coordinator.notify(app: "Obsidian", title: "Não foi possível anotar")
        }
        NotchPanelController.current?.resignKey()
    }
}

private struct ResultRow<Actions: View>: View {
    let result: SpotlightSearch.Result
    let selected: Bool
    let onOpen: () -> Void
    let onQuickLook: () -> Void
    @ViewBuilder let actionButtons: () -> Actions

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    ResultIcon(url: result.id)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.name).font(.system(size: 12)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                        Text("\(result.kind) · \(result.id.deletingLastPathComponent().lastPathComponent)")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchButtonStyle())

            if hovering {
                Button(action: onQuickLook) {
                    Image(systemName: "eye").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(NotchButtonStyle())
                .help("Quick Look ␣")
            }

            Menu {
                actionButtons()
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? .white.opacity(0.12) : .white.opacity(0.06)))
        .contextMenu { actionButtons() }
        .onHover { hovering = $0 }
    }
}

private struct ResultIcon: View {
    let url: URL

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable().frame(width: 16, height: 16)
    }
}
