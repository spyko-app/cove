import Foundation

struct ActivityQueue {
    struct Entry {
        let activity: NotchActivity
        let duration: Double
        let enqueuedAt: Date
    }

    enum Decision: Equatable {
        case showNow
        case enqueue
    }

    private(set) var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }

    func decision(for a: NotchActivity, current: NotchActivity?) -> Decision {
        if a.isHUD { return .showNow }
        guard let current else { return .showNow }
        if current.isHUD { return .showNow }
        if current == a { return .showNow }
        return .enqueue
    }

    mutating func enqueue(_ a: NotchActivity, duration: Double, now: Date) {
        let key = a.kindKey
        if let idx = entries.firstIndex(where: { $0.activity.kindKey == key }) {
            entries[idx] = Entry(activity: a, duration: duration, enqueuedAt: now)
        } else {
            entries.append(Entry(activity: a, duration: duration, enqueuedAt: now))
        }
    }

    mutating func removeAll(kindKey: String) {
        entries.removeAll { $0.activity.kindKey == kindKey }
    }

    mutating func next(now: Date) -> Entry? {
        while !entries.isEmpty {
            let candidate = entries.removeFirst()
            if now.timeIntervalSince(candidate.enqueuedAt) > candidate.duration * 2 {
                continue
            }
            return candidate
        }
        return nil
    }
}

extension NotchActivity {
    var kindKey: String {
        switch self {
        case .volume: "volume"
        case .brightness: "brightness"
        case .battery: "battery"
        case .lowPowerMode: "lowPowerMode"
        case .device: "device"
        case .focus: "focus"
        case .lock: "lock"
        case .event: "event"
        case .eventCountdown: "eventCountdown"
        case .notification: "notification"
        case .track: "track"
        case .keyboardBrightness: "keyboardBrightness"
        case .timer: "timer"
        case .recording: "recording"
        case .screenRecording: "screenRecording"
        case .wifi: "wifi"
        case .hotspot: "hotspot"
        case .drive: "drive"
        case .vpn: "vpn"
        case .vpnSession: "vpnSession"
        case .highAlert: "highAlert"
        }
    }
}

extension NotchActivity {
    var redactedForLockScreen: NotchActivity {
        switch self {
        case .event(_, let minutes):
            .event(title: "Evento", minutes: minutes)
        case .eventCountdown(_, let start, let meetingURL):
            .eventCountdown(title: "Evento", start: start, meetingURL: meetingURL)
        case .timer(_, let remaining):
            .timer(label: "", remaining: remaining)
        case .drive(_, let mounted):
            .drive(name: "Disco", mounted: mounted)
        case .device(_, let connected, let battery):
            .device(name: "Dispositivo", connected: connected, battery: battery)
        case .wifi(_, let connected):
            .wifi(ssid: nil, connected: connected)
        case .notification(let app, _):
            .notification(app: app, title: "")
        default:
            self
        }
    }
}
