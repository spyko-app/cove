import SwiftTerm
import SwiftUI

/// Instância única do shell — sobrevive à troca de páginas pra não matar o processo.
@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate, ObservableObject {
    static let shared = TerminalSession()

    let view: LocalProcessTerminalView = {
        let v = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        v.font = NSFont(name: "Menlo", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        v.nativeBackgroundColor = .black
        v.nativeForegroundColor = .white
        return v
    }()

    /// cwd do shell da ilha, atualizado via OSC 7 (`hostCurrentDirectoryUpdate`).
    /// Cai pro home quando o shell ainda não emitiu nenhum OSC 7.
    @Published private(set) var currentDirectory: String = NSHomeDirectory()

    private var started = false

    override private init() {
        super.init()
        view.processDelegate = self
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        // precmd emite OSC 7 (file://host/cwd) a cada prompt novo. O hook vive num
        // .zshrc próprio via ZDOTDIR (não em `-c ...; exec zsh`, que perderia a função):
        // o rc devolve ZDOTDIR ao HOME, carrega os rcs do usuário e só então registra o hook.
        // capturado ANTES de remover ZDOTDIR do env — se o usuário já customiza
        // ZDOTDIR (oh-my-zsh, prezto etc.), o rc gerado precisa devolver pra ELE,
        // não pro HOME (senão os rcs reais do usuário nunca são carregados).
        let userZDOTDIR = ProcessInfo.processInfo.environment["ZDOTDIR"] ?? NSHomeDirectory()
        var env = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        if !env.contains(where: { $0.hasPrefix("TERM=") }) { env.append("TERM=xterm-256color") }
        if !env.contains(where: { $0.hasPrefix("COLORTERM=") }) { env.append("COLORTERM=truecolor") }
        if let rcDir = Self.makeZDOTDIR(userZDOTDIR: userZDOTDIR) {
            env.removeAll { $0.hasPrefix("ZDOTDIR=") }
            env.append("ZDOTDIR=\(rcDir.path)")
        }
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-l", "-i"],
            environment: env,
            execName: nil,
            currentDirectory: NSHomeDirectory()
        )
    }

    /// Diretório temporário com um .zshrc que encadeia os rcs do usuário + hook OSC 7.
    /// `userZDOTDIR` é o ZDOTDIR real do usuário (ou HOME se ele não define um).
    private static func makeZDOTDIR(userZDOTDIR: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cove-zsh", isDirectory: true)
        let rc = """
        export ZDOTDIR="\(userZDOTDIR)"
        [ -f "$ZDOTDIR/.zshenv" ] && source "$ZDOTDIR/.zshenv"
        [ -f "$ZDOTDIR/.zprofile" ] && source "$ZDOTDIR/.zprofile"
        [ -f "$ZDOTDIR/.zshrc" ] && source "$ZDOTDIR/.zshrc"
        [ -f "$ZDOTDIR/.zlogin" ] && source "$ZDOTDIR/.zlogin"
        autoload -Uz add-zsh-hook
        _cove_osc7() { printf '\\e]7;file://%s%s\\a' "$HOST" "$PWD"; }
        add-zsh-hook precmd _cove_osc7
        _cove_osc7
        """
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try rc.write(to: dir.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
            return dir
        } catch { return nil }
    }

    func terminate() {
        guard started else { return }
        view.terminate()
    }

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {}
    nonisolated func scrolled(source: TerminalView, position: Double) {}
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let url = URL(string: directory), url.isFileURL else { return }
        let path = url.path
        Task { @MainActor in
            self.currentDirectory = path
        }
    }
}

struct TerminalPage: View {
    let notchTop: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TerminalHostView(notchTop: notchTop)
            TerminalHandoffMenu()
                .padding(.top, notchTop + 4)
                .padding(.trailing, 14)
        }
    }
}

/// Menu "↗" — abre o cwd atual da ilha num terminal externo, ou copia o caminho.
private struct TerminalHandoffMenu: View {
    @ObservedObject private var session = TerminalSession.shared
    @State private var installed: [TerminalApp] = TerminalApp.installed()

    var body: some View {
        Menu {
            ForEach(installed, id: \.self) { app in
                Button("Abrir no \(app.label)") {
                    TerminalApp.launch(app: app, cwd: session.currentDirectory)
                }
            }
            if !installed.isEmpty {
                Divider()
            }
            Button("Copiar cwd") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(session.currentDirectory, forType: .string)
            }
        } label: {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Abrir no terminal externo")
        .onAppear { installed = TerminalApp.installed() }
    }
}

private struct TerminalHostView: NSViewRepresentable {
    let notchTop: CGFloat

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        TerminalSession.shared.startIfNeeded()
        let t = TerminalSession.shared.view
        // instância única sobrevive à troca de página — nunca deixa constraint
        // morta apontando pra um container antigo ao reentrar (Droppy lição #TerminalPage).
        if t.superview !== container {
            if let old = t.superview {
                NSLayoutConstraint.deactivate(old.constraints.filter { $0.firstItem === t || $0.secondItem === t })
                t.removeFromSuperview()
            }
            t.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(t)
            NSLayoutConstraint.activate([
                t.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                t.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                t.topAnchor.constraint(equalTo: container.topAnchor, constant: notchTop + 4),
                t.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            ])
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
