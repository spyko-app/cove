import SwiftUI

private struct AnchorView: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onResolve(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ShelfPage: View {
    @ObservedObject var shelf: ShelfStore
    @StateObject private var thumbnails = ThumbnailCache.shared
    let notchTop: CGFloat
    @State private var selection = SelectionModel<UUID>()
    @State private var errorClearTask: Task<Void, Never>?
    @State private var shareAnchor: NSView?

    private var orderedIDs: [UUID] { shelf.items.map(\.id) }

    private var widgets: [String] { shelf.layout.widgets }
    private var quickActionIDs: [String] { shelf.layout.actions }

    private var actionTargetIDs: [UUID] {
        selection.selected.isEmpty ? shelf.items.map(\.id) : Array(selection.selected)
    }

    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: notchTop)
            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 22)).foregroundStyle(.white.opacity(0.5))
                    Text("Arraste arquivos pra cá").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxHeight: .infinity)
            } else {
                ForEach(widgets, id: \.self) { widget in
                    widgetView(widget)
                }
            }
            if let error = shelf.lastError {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.red.opacity(0.15)))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
            }
        }
        .onExitCommand { selection.clear() }
        .onAppear { shelf.startObservingConfig() }
        .onDisappear {
            shelf.stopObservingConfig()
            errorClearTask?.cancel()
        }
        .onChange(of: shelf.lastError) { _, newValue in
            errorClearTask?.cancel()
            guard newValue != nil else { return }
            errorClearTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                shelf.lastError = nil
            }
        }
    }

    @ViewBuilder
    private func widgetView(_ id: String) -> some View {
        switch id {
        case "quickActions": quickActionsRow
        case "recent": recentStrip
        default: filesGrid
        }
    }

    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            ForEach(quickActionIDs, id: \.self) { action in
                Button {
                    perform(action)
                } label: {
                    Image(systemName: symbol(for: action))
                        .font(.system(size: 13))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.75))
                .background(Circle().fill(.white.opacity(0.08)))
                .help(label(for: action))
            }
            Spacer()
        }
        .padding(.horizontal, 18)
    }

    private var recentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(shelf.items.suffix(5).reversed()) { item in
                    Image(nsImage: thumbnails.icon(for: item.url))
                        .resizable().frame(width: 24, height: 24)
                        .task { thumbnails.request(item.url) }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func symbol(for action: String) -> String {
        switch action {
        case "airdrop": return "airplayaudio"
        case "finder": return "folder"
        case "compress": return "doc.zipper"
        case "copyPath": return "doc.on.clipboard"
        case "delete": return "trash"
        case "share": return "square.and.arrow.up"
        default: return "questionmark"
        }
    }

    private func label(for action: String) -> String {
        switch action {
        case "airdrop": return "AirDrop"
        case "finder": return "Mostrar no Finder"
        case "compress": return "Compactar (zip)"
        case "copyPath": return "Copiar caminho"
        case "delete": return "Remover"
        case "share": return "Compartilhar"
        default: return action
        }
    }

    private func perform(_ action: String) {
        let ids = actionTargetIDs
        guard !ids.isEmpty else { return }
        switch action {
        case "airdrop": shelf.airDrop(ids)
        case "finder":
            let urls = shelf.items.filter { ids.contains($0.id) }.map(\.url)
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case "compress": shelf.compress(ids)
        case "copyPath": shelf.copyPaths(ids)
        case "delete":
            for id in ids { shelf.remove(id) }
            selection.clear()
        case "share": share(ids)
        default: break
        }
    }

    private var filesGrid: some View {
        Group {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(shelf.items) { item in
                            let isSelected = selection.isSelected(item.id)
                            VStack(spacing: 4) {
                                Image(nsImage: thumbnails.icon(for: item.url))
                                    .resizable().frame(width: 40, height: 40)
                                    .task { thumbnails.request(item.url) }
                                Text(item.url.lastPathComponent).font(.system(size: 9)).lineLimit(1)
                                    .foregroundStyle(.white.opacity(0.8)).frame(width: 64)
                            }
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? .white.opacity(0.15) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? .white.opacity(0.6) : .clear, lineWidth: 1.5))
                            .contentShape(Rectangle())
                            .onDrag {
                                dragURLs(startingWith: item.id)
                            } preview: {
                                dragPreview(startingWith: item.id)
                            }
                            .contextMenu {
                                if ["png", "jpg", "jpeg"].contains(item.url.pathExtension.lowercased()) {
                                    Button("Editar…") {
                                        CaptureEditorManager.shared.open(image: item.url) { edited in
                                            shelf.add([edited])
                                        }
                                    }
                                }
                                let ids = selection.isSelected(item.id) && selection.selected.count > 1 ? Array(selection.selected) : [item.id]
                                Button(ids.count > 1 ? "AirDrop (\(ids.count))" : "AirDrop") { shelf.airDrop(ids) }
                                Button("Compartilhar…") { share(ids) }
                                if ids.count == 1 {
                                    Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                }
                                Button(ids.count > 1 ? "Remover (\(ids.count))" : "Remover", role: .destructive) {
                                    for id in ids { shelf.remove(id) }
                                    selection.clear()
                                }
                            }
                            .simultaneousGesture(TapGesture(count: 2).onEnded { NSWorkspace.shared.open(item.url) })
                            .simultaneousGesture(TapGesture(count: 1).onEnded {
                                let flags = NSEvent.modifierFlags
                                selection.click(item.id, ordered: orderedIDs, shift: flags.contains(.shift), command: flags.contains(.command))
                            })
                        }
                    }
                    .padding(.horizontal, 16)
                }
                HStack {
                    if !selection.selected.isEmpty {
                        Button("AirDrop (\(selection.selected.count))") { shelf.airDrop(Array(selection.selected)) }
                        Button("Remover (\(selection.selected.count))") {
                            for id in selection.selected { shelf.remove(id) }
                            selection.clear()
                        }
                    } else {
                        Button("AirDrop tudo") { shelf.airDrop(shelf.items.map(\.id)) }
                    }
                    Spacer()
                    Button("Limpar") { shelf.clear(); selection.clear() }
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7)).padding(.horizontal, 18).padding(.bottom, 8)
                .background(AnchorView { shareAnchor = $0 }.frame(width: 1, height: 1))
        }
    }

    private func share(_ ids: [UUID]) {
        guard let shareAnchor else { return }
        shelf.share(ids, from: shareAnchor, rect: shareAnchor.bounds)
    }

    private func dragURLs(startingWith id: UUID) -> NSItemProvider {
        let ids = selection.isSelected(id) && selection.selected.count > 1 ? Array(selection.selected) : [id]
        let urls = shelf.items.filter { ids.contains($0.id) }.map(\.url)
        guard let first = urls.first else { return NSItemProvider() }
        let pb = NSPasteboard(name: .drag)
        pb.clearContents()
        if urls.count > 1 {
            pb.writeObjects(urls as [NSURL])
        }
        return NSItemProvider(object: first as NSURL)
    }

    @ViewBuilder
    private func dragPreview(startingWith id: UUID) -> some View {
        let ids = selection.isSelected(id) && selection.selected.count > 1 ? Array(selection.selected) : [id]
        let urls = shelf.items.filter { ids.contains($0.id) }.map(\.url)
        let firstURL = urls.first
        ZStack(alignment: .topTrailing) {
            if let firstURL {
                Image(nsImage: thumbnails.icon(for: firstURL))
                    .resizable().frame(width: 48, height: 48)
            }
            if ids.count > 1 {
                Text("\(ids.count)")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(.blue))
                    .offset(x: 6, y: -6)
            }
        }
        .padding(6)
    }
}
