import AppKit
import Foundation
import os

/// Terminais externos suportados pro handoff da ilha (T32).
enum TerminalApp: String, CaseIterable {
    case wezterm
    case kitty
    case alacritty
    case iterm
    case terminal

    var bundleID: String {
        switch self {
        case .wezterm: return "com.github.wez.wezterm"
        case .kitty: return "net.kovidgoyal.kitty"
        case .alacritty: return "org.alacritty"
        case .iterm: return "com.googlecode.iterm2"
        case .terminal: return "com.apple.Terminal"
        }
    }

    var label: String {
        switch self {
        case .wezterm: return "WezTerm"
        case .kitty: return "kitty"
        case .alacritty: return "Alacritty"
        case .iterm: return "iTerm"
        case .terminal: return "Terminal"
        }
    }

    /// Lista os terminais instalados no Mac, na ordem do enum.
    static func installed() -> [TerminalApp] {
        allCases.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    /// Monta o executável + argumentos pra abrir `app` já no diretório `cwd`.
    /// Puro: não lança processo, só resolve o caminho do app instalado.
    static func launchArguments(app: TerminalApp, cwd: String) -> (executable: URL?, arguments: [String])? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
            return nil
        }
        return launchArguments(app: app, appURL: appURL, cwd: cwd)
    }

    /// Variante testável: recebe a URL do `.app` já resolvida (real ou fake),
    /// sem depender do `NSWorkspace` — é o que os testes exercitam.
    static func launchArguments(app: TerminalApp, appURL: URL, cwd: String) -> (executable: URL?, arguments: [String]) {
        switch app {
        case .wezterm:
            let bin = appURL.appendingPathComponent("Contents/MacOS/wezterm")
            return (bin, ["start", "--cwd", cwd])
        case .kitty:
            let bin = appURL.appendingPathComponent("Contents/MacOS/kitty")
            return (bin, ["--directory", cwd])
        case .alacritty:
            let bin = appURL.appendingPathComponent("Contents/MacOS/alacritty")
            return (bin, ["--working-directory", cwd])
        case .iterm, .terminal:
            return (URL(fileURLWithPath: "/usr/bin/open"), ["-a", appURL.path, cwd])
        }
    }

    /// Lança o terminal já no `cwd`. Roda fora da main thread; erro é só logado.
    static func launch(app: TerminalApp, cwd: String) {
        guard let (executable, arguments) = launchArguments(app: app, cwd: cwd), let executable else {
            Logger.terminalHandoff.error("handoff: \(app.label, privacy: .public) não instalado ou sem CLI")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            do {
                try process.run()
            } catch {
                Logger.terminalHandoff.error("handoff: falha ao abrir \(app.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension Logger {
    static let terminalHandoff = Logger(subsystem: "app.cove.notch", category: "terminal-handoff")
}
