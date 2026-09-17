import Foundation
import IOKit.pwr_mgt

@MainActor
final class HighAlert: ObservableObject {
    enum Duration: Int, CaseIterable, Codable {
        case m15 = 15, m30 = 30, m60 = 60, infinite = 0

        var label: String {
            switch self {
            case .m15: "15m"
            case .m30: "30m"
            case .m60: "1h"
            case .infinite: "∞"
            }
        }
    }

    @Published private(set) var isOn = false
    @Published private(set) var expiresAt: Date?
    var lastDuration: Duration = .infinite
    private var assertion: IOPMAssertionID = 0
    private var expiryTask: Task<Void, Never>?

    nonisolated static func expiry(from start: Date, duration: Duration) -> Date? {
        guard duration != .infinite else { return nil }
        return start.addingTimeInterval(TimeInterval(duration.rawValue * 60))
    }

    func toggle() {
        if isOn { set(false) } else { start(lastDuration) }
    }

    func start(_ duration: Duration, now: Date = Date()) {
        expiryTask?.cancel(); expiryTask = nil
        if !isOn {
            let ok = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), "Cove High Alert" as CFString, &assertion)
            guard ok == kIOReturnSuccess else { return }
            isOn = true
        }
        let expiry = Self.expiry(from: now, duration: duration)
        expiresAt = expiry
        guard let expiry else { return }
        expiryTask = Task { [weak self] in
            let seconds = expiry.timeIntervalSinceNow
            if seconds > 0 {
                try? await Task.sleep(for: .seconds(seconds))
            }
            guard !Task.isCancelled else { return }
            self?.set(false)
        }
    }

    func set(_ on: Bool) {
        if on, !isOn {
            start(lastDuration)
        } else if !on, isOn {
            IOPMAssertionRelease(assertion); assertion = 0; isOn = false
            expiresAt = nil
            expiryTask?.cancel(); expiryTask = nil
        }
    }
}
