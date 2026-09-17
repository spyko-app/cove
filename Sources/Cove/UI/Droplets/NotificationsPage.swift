import SwiftUI

/// Droplet de notificações — histórico recente de todos os apps (via
/// `NotificationMirror.recent`), buscável e agrupado por app.
struct NotificationsPage: View {
    @ObservedObject var mirror: NotificationMirror
    let notchTop: CGFloat
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    // T34 — responder iMessage direto do droplet, via ScriptingBridge (Messages.app).
    private let messagesBridge = MessagesBridge()
    @State private var replyingID: Int?
    @State private var replyText = ""
    @State private var replyBanner: String?
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: notchTop)

            if !mirror.available {
                VStack(spacing: 6) {
                    Label("Ative Acesso Total ao Disco pro Cove ver as notificações.",
                          systemImage: "lock.shield")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    Button("Abrir Privacidade…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            mirror.recheck()
                        }
                    }
                    .controlSize(.small)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 16)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    TextField("Buscar…", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                        .focused($searchFocused)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.08)))
                .padding(.horizontal, 16)

                let groups = NotificationMirror.group(mirror.recent, query: query)

                if groups.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "bell.badge").font(.system(size: 22)).foregroundStyle(.white.opacity(0.5))
                        Text(query.isEmpty ? "Sem notificações ainda" : "Nada encontrado")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(groups, id: \.bundleID) { group in
                                appSection(group.bundleID, group.notes)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    if let replyBanner {
                        Text(replyBanner)
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 18).padding(.bottom, 2)
                    }
                    HStack {
                        Spacer()
                        Button("Limpar tudo") { mirror.clearHistory() }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 18).padding(.bottom, 8)
                }
            }
        }
        .onAppear {
            NotchPanelController.current?.makeKey()
            searchFocused = true
            mirror.recheck()
        }
        .onDisappear { NotchPanelController.current?.resignKey() }
    }

    @ViewBuilder
    private func appSection(_ bundleID: String, _ notes: [NotificationMirror.Note]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                appIcon(bundleID)
                Text(notes.first?.app ?? bundleID)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Text("\(notes.count)")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                Spacer()
            }
            ForEach(notes) { n in row(n, bundleID: bundleID) }
        }
    }

    @ViewBuilder
    private func appIcon(_ bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 14, height: 14)
        } else {
            Image(systemName: "app.dashed").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private func row(_ n: NotificationMirror.Note, bundleID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { openApp(bundleID) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        if !n.body.isEmpty {
                            Text(n.body).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                        }
                    }
                    Spacer()
                    Text(n.date, format: .dateTime.hour().minute())
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchButtonStyle())
            .contextMenu {
                Button("Abrir app") { openApp(bundleID) }
                if bundleID == MessagesBridge.bundleID {
                    Button("Responder") { startReply(n) }
                }
                Button("Limpar deste app") { mirror.clear(bundleID: bundleID) }
            }

            if bundleID == MessagesBridge.bundleID, replyingID == n.id {
                replyField(for: n)
            }
        }
    }

    /// T34 — campo inline de resposta pra uma notificação do Mensagens. Se o
    /// app não está rodando, oferece "Abrir Mensagens" em vez do campo (nunca
    /// auto-lança via ScriptingBridge).
    @ViewBuilder
    private func replyField(for n: NotificationMirror.Note) -> some View {
        if !messagesBridge.isAvailable {
            Button("Abrir Mensagens") { openApp(MessagesBridge.bundleID); replyingID = nil }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 8)
        } else {
            HStack(spacing: 6) {
                TextField("Responder…", text: $replyText)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                    .focused($replyFocused)
                    .onSubmit { send(n) }
                    .onExitCommand { replyingID = nil; replyText = "" }
                Button("Enviar") { send(n) }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(replyText.isEmpty ? 0.4 : 0.9))
                    .disabled(replyText.isEmpty)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.08)))
            .padding(.horizontal, 8)
            .onAppear { replyFocused = true }
        }
    }

    private func startReply(_ n: NotificationMirror.Note) {
        replyingID = n.id
        replyText = ""
        replyBanner = nil
    }

    /// Envia a resposta via `MessagesBridge` — nunca toca `chat.db`, só a
    /// notificação já espelhada define o destinatário (nome ou handle).
    private func send(_ n: NotificationMirror.Note) {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let target = MessageTarget.handle(fromNotificationTitle: n.title, body: n.body) ?? n.title
        do {
            try messagesBridge.send(text, toHandle: target)
            replyBanner = "Mensagem enviada"
        } catch {
            replyBanner = (error as? MessagesError)?.errorDescription ?? "Não deu pra enviar a mensagem."
        }
        replyingID = nil
        replyText = ""
    }

    private func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
