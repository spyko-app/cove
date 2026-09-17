import AppKit
import ServiceManagement
import SwiftUI

@main
struct Entry {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["media-test"] {
            // Prova viva do MediaRemote sem UI.
            _ = NSApplication.shared
            let svc = MainActor.assumeIsolated { MediaRemoteService() }
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            let np = MainActor.assumeIsolated { svc.nowPlaying }
            print("título: \(np.title) · artista: \(np.artist) · tocando: \(np.isPlaying) · artwork: \(np.artwork != nil)")
            exit(np.title.isEmpty ? 1 : 0)
        }
        CoveApp.main()
    }
}

struct CoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            Text("Cove \(AppVersion.marketing)")
            Divider()
            Button("Ajustes…") {
                SettingsWindowManager.shared.show(coordinator: AppDelegate.sharedCoordinator)
            }
            .keyboardShortcut(",")
            Button("Verificar atualizações…") { Updater.shared?.checkForUpdates() }
            Divider()
            Button("Sair do Cove") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "capsule.fill")
        }
    }
}

/// Menu de configurações da ilha (toggles das features + limiares).

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchPanelController?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Self.sharedCoordinator.shutdown() }  // devolve o HUD nativo
    }
    // Fonte ÚNICA — o menu e os painéis compartilham; nunca criar segundo
    // coordinator (dobraria adapter perl, listeners e timers).
    @MainActor static let sharedCoordinator = NotchCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let c = NotchPanelController(coordinator: Self.sharedCoordinator)
        c.show()
        controller = c
        NotchPanelController.current = c
        OnboardingWindowManager.shared.showIfNeeded(coordinator: Self.sharedCoordinator)
        if Self.sharedCoordinator.config.launchAtLogin, SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        if ProcessInfo.processInfo.environment["COVE_OPEN_SETTINGS"] == "1" {
            SettingsWindowManager.shared.show(coordinator: Self.sharedCoordinator)
        }
        // Instancia o updater no boot só no app empacotado (Updater.shared já
        // guarda isso); dispara o ciclo de checagem agendada do Sparkle
        // (SUScheduledCheckInterval), sem checagem automática silenciosa.
        _ = Updater.shared
        // T2.0: provas do Rosto — só com COVE_ROSTO_SPIKE (1 = as três · a/b/c = uma) e só no .app (TCC real).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            RostoSpike.run()
        }
        // reposição em wake/lid-close/reconexão de tela: caminho único é
        // NotchPanelController.scheduleReload() (debounce + reload idempotente).
    }
}

/// Versão vinda do Info.plist (única fonte: VERSION → make-app.sh); nunca hardcode na UI.
enum AppVersion {
    static let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
}
