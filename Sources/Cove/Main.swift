import AppKit
import ServiceManagement
import SwiftUI

@main
struct Entry {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["media-test"] {
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchPanelController?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Self.sharedCoordinator.shutdown() }
    }
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
        _ = Updater.shared
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            RostoSpike.run()
        }
    }
}

enum AppVersion {
    static let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
}
