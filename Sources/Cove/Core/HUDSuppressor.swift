import Darwin
import Foundation

/// Suprime o HUD nativo de volume/brilho (técnica SlimHUD): kickstart do
/// OSDUIHelper + SIGSTOP — o helper existe mas nunca desenha. Watchdog de 10s
/// re-congela se o sistema relançar. No exit, SIGCONT devolve o HUD ao sistema.
@MainActor
final class HUDSuppressor {
    private var timer: Timer?
    private(set) var active = false

    func enable() {
        // nunca congela o HUD do sistema rodando como binário dev (swift run)
        guard AppEnvironment.isBundledApp else { return }
        guard !active else { return }
        active = true
        Self.installSignalHandlers()
        freeze()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.freeze() }
        }
    }

    func disable() {
        active = false
        timer?.invalidate()
        timer = nil
        signalHelper(SIGCONT)
    }

    private func freeze() {
        guard active else { return }
        if helperPID() == nil {
            _ = run("/bin/launchctl", ["kickstart", "gui/\(getuid())/com.apple.OSDUIHelper"])
            usleep(200_000)
        }
        signalHelper(SIGSTOP)
    }

    private func helperPID() -> pid_t? {
        let out = run("/usr/bin/pgrep", ["-x", "OSDUIHelper"])
        return pid_t(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // pid congelado guardado pro handler de sinal (que só pode chamar
    // funções async-signal-safe: kill/_exit — nada de Process/ObjC)
    nonisolated(unsafe) static var frozenPID: pid_t = 0

    /// PID pode ser reutilizado entre pgrep e kill — confirma o nome pelo caminho do processo.
    private static func isOSDUIHelper(_ pid: pid_t) -> Bool {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return false }
        return String(cString: buf).hasSuffix("/OSDUIHelper")
    }

    private func signalHelper(_ sig: Int32) {
        if let pid = helperPID(), Self.isOSDUIHelper(pid) {
            kill(pid, sig)
            Self.frozenPID = sig == SIGSTOP ? pid : 0
        }
    }

    /// SIGTERM/SIGINT não passam pelo applicationWillTerminate de MenuBarExtra
    /// (provado: pkill vazou o helper congelado) — handler C devolve SIGCONT.
    private static var handlersInstalled = false
    private static func installSignalHandlers() {
        guard !handlersInstalled else { return }
        handlersInstalled = true
        for sig in [SIGTERM, SIGINT] {
            signal(sig) { s in
                if HUDSuppressor.frozenPID > 0 { kill(HUDSuppressor.frozenPID, SIGCONT) }
                _exit(s)
            }
        }
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
