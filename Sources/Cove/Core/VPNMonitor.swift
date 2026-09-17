import Foundation
import SystemConfiguration

@MainActor
final class VPNMonitor {
    enum VPNEvent: Equatable { case up, down }

    var onEvent: ((VPNEvent) -> Void)?

    private(set) var isUp = false
    private(set) var sessionStart: Date?

    private var store: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?

    init() {
        var context = SCDynamicStoreContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "CoveVPN" as CFString, { _, _, info in
            guard let info else { return }
            let monitor = Unmanaged<VPNMonitor>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }, &context) else {
            FileHandle.standardError.write(Data("VPNMonitor: falha ao criar SCDynamicStore\n".utf8))
            return
        }
        self.store = store

        let patterns = [
            "State:/Network/Interface/utun[0-9]+/IPv4",
            "State:/Network/Interface/utun[0-9]+/IPv6",
        ] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, nil, patterns) else {
            FileHandle.standardError.write(Data("VPNMonitor: falha ao registrar notificação\n".utf8))
            return
        }
        guard let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) else {
            FileHandle.standardError.write(Data("VPNMonitor: falha ao criar run loop source\n".utf8))
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        prime()
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func refresh() {
        let active = currentActiveInterfaces()
        guard let event = Self.transition(previous: isUp, activeInterfaces: active) else { return }
        isUp = event == .up
        sessionStart = isUp ? Date() : nil
        onEvent?(event)
    }

    private func prime() {
        isUp = Self.primeState(activeInterfaces: currentActiveInterfaces())
        sessionStart = nil
    }

    private func currentActiveInterfaces() -> Set<String> {
        guard let store else { return [] }
        let keys = (SCDynamicStoreCopyKeyList(
            store, "State:/Network/Interface/utun[0-9]+/IPv[46]" as CFString) as? [String]) ?? []
        return Set(Self.interfaceNames(fromKeys: keys))
    }

    static func primeState(activeInterfaces: Set<String>) -> Bool {
        !activeInterfaces.isEmpty
    }

    static func interfaceNames(fromKeys keys: [String]) -> [String] {
        keys.compactMap { key in
            let parts = key.split(separator: "/")
            guard parts.count >= 4, parts[3].hasPrefix("utun") else { return nil }
            return String(parts[3])
        }
    }

    static func transition(previous: Bool, activeInterfaces: Set<String>) -> VPNEvent? {
        let next = !activeInterfaces.isEmpty
        guard next != previous else { return nil }
        return next ? .up : .down
    }
}
