import Foundation
import Sparkle

/// Wrapper do Sparkle 2. Só existe no app empacotado — nunca em testes/dev
/// binary (Sparkle exige bundle .app válido com Info.plist assinado).
@MainActor
final class Updater: NSObject {

    static let shared: Updater? = AppEnvironment.isBundledApp ? Updater() : nil

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Canal de atualização (`stable` por padrão, `nightly` opt-in). Lido de
/// `UserDefaults` — `Config.swift` é propriedade de outra frente (T27); o
/// toggle na tela de Ajustes vem depois. Ver task-30-brief.md.
enum UpdateChannel {
    static let defaultsKey = "updateChannel"

    static var current: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? "stable"
    }
}

/// Checagem pura usada por `scripts/make-app.sh` (via teste) pra garantir
/// que VERSION e Resources/Info.plist nunca divergem (lições #5/#16).
enum VersionCheck {
    static func matches(plist: String, version: String) -> Bool {
        let a = plist.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return a == b
    }
}

extension Updater: SPUUpdaterDelegate {
    // nonisolated: Sparkle chama de fora do MainActor. UserDefaults é
    // thread-safe e UpdateChannel não é isolado — sem assumeIsolated.
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UpdateChannel.current == "nightly" ? ["nightly"] : []
    }
}
