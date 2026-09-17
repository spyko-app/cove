import Foundation
import IOKit.ps

@MainActor
final class PowerService: ObservableObject {
    struct BatteryState: Equatable {
        var percent = 100
        var charging = false
        var onAC = true
    }

    var onBatteryEvent: ((BatteryState) -> Void)?
    var onLowPowerMode: ((Bool) -> Void)?
    @Published private(set) var state: BatteryState?

    private var last = BatteryState()
    private var source: CFRunLoopSource?

    init() {
        state = Self.read()
        last = state ?? BatteryState()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let me = Unmanaged<PowerService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in me.tick() }
        }, ctx)?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            let low = ProcessInfo.processInfo.isLowPowerModeEnabled
            Task { @MainActor in self?.onLowPowerMode?(low) }
        }
    }

    static func read() -> BatteryState? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?
                .takeUnretainedValue() as? [String: Any],
                desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            var s = BatteryState()
            s.percent = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
            s.charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            s.onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return s
        }
        return nil
    }

    private func tick() {
        guard let now = Self.read() else { return }
        defer { last = now }
        if state != now { state = now }
        if now.onAC != last.onAC || now.charging != last.charging {
            onBatteryEvent?(now)
        } else if now.percent != last.percent, !now.onAC,
                  now.percent <= NotchConfigStore.load().lowBatteryThreshold,
                  now.percent % 5 == 0 {
            onBatteryEvent?(now)
        }
    }
}
