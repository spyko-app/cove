import Foundation
import Sparkle

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

enum UpdateChannel {
    static let defaultsKey = "updateChannel"

    static var current: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? "stable"
    }
}

enum VersionCheck {
    static func matches(plist: String, version: String) -> Bool {
        let a = plist.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return a == b
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UpdateChannel.current == "nightly" ? ["nightly"] : []
    }
}
