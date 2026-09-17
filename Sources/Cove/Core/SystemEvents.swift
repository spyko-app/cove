import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class SystemEvents: ObservableObject {
    var onFocusChange: ((Bool) -> Void)?
    var onScreenLock: ((Bool) -> Void)?
    var onHourlyChime: (() -> Void)?

    @Published private(set) var isScreenLocked: Bool = SystemEvents.isScreenActuallyLocked()
    @Published private(set) var isFocusActive = false

    private var focusTimer: Timer?
    private var chimeTimer: Timer?
    private var lastFocus: Bool?

    private var assertionsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    }

    init() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) {
            [weak self] _ in Task { @MainActor in await self?.confirmAndPublishLock() }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) {
            [weak self] _ in Task { @MainActor in self?.setLocked(false); self?.onScreenLock?(false) }
        }
        let wsnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            wsnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.rederiveLock() }
            }
        }
        dnc.addObserver(forName: .init("com.apple.screensaver.didstop"), object: nil, queue: .main) {
            [weak self] _ in Task { @MainActor in self?.rederiveLock() }
        }
        isFocusActive = focusActive
        focusTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkFocus() }
        }
        scheduleChime()
    }

    private func setLocked(_ locked: Bool) {
        if isScreenLocked != locked { isScreenLocked = locked }
    }

    private func confirmAndPublishLock() async {
        if Self.isScreenActuallyLocked() {
            setLocked(true); onScreenLock?(true)
            return
        }
        try? await Task.sleep(for: .milliseconds(500))
        guard Self.isScreenActuallyLocked(), !isScreenLocked else { return }
        setLocked(true); onScreenLock?(true)
    }

    private func rederiveLock() {
        setLocked(Self.isScreenActuallyLocked())
    }

    nonisolated static func isScreenActuallyLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    var focusActive: Bool {
        guard let data = try? Data(contentsOf: assertionsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = (obj["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]]
        else { return false }
        return !records.isEmpty
    }

    private func checkFocus() {
        let now = focusActive
        if isFocusActive != now { isFocusActive = now }
        if let last = lastFocus, last != now {
            onFocusChange?(now)
        }
        lastFocus = now
    }

    private func scheduleChime() {
        let cal = Calendar.current
        let nextHour = cal.nextDate(after: Date(), matching: DateComponents(minute: 0, second: 0),
                                    matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        chimeTimer = Timer(fire: nextHour, interval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onHourlyChime?() }
        }
        RunLoop.main.add(chimeTimer!, forMode: .common)
    }

    private static var cache: [String: NSSound] = [:]

    static func playSound(_ name: String) {
        if let s = cache[name] { s.stop(); s.play(); return }
        if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"),
           let s = NSSound(contentsOf: url, byReference: true) {
            cache[name] = s
            s.play()
        } else {
            NSSound(named: name)?.play()
        }
    }
}
