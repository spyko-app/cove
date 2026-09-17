import Foundation

enum WideIslandMode: String, Codable, CaseIterable {
    case off
    case externalOnly
    case always

    var label: String {
        switch self {
        case .off: "Desligada"
        case .externalOnly: "Só em telas externas"
        case .always: "Sempre"
        }
    }
}

enum WideIslandLayout {
    static let extraWidth: CGFloat = 120

    static func isWide(mode: WideIslandMode, simulated: Bool) -> Bool {
        switch mode {
        case .off: false
        case .externalOnly: simulated
        case .always: true
        }
    }

    static func label(for a: NotchActivity) -> String {
        switch a {
        case .timer(let label, _): label.isEmpty ? "Timer" : label
        case .highAlert: "High Alert"
        case .recording: "Gravando"
        case .screenRecording: "Gravando tela"
        case .vpnSession: "VPN"
        case .eventCountdown(let title, _, _): title
        default: ActivityExpansion.regions(for: a).title
        }
    }
}

enum WideIslandContent: Equatable {
    case media
    case activity(NotchActivity)
    case mediaAndActivity(NotchActivity)

    var animationKey: String {
        switch self {
        case .media: "media"
        case .activity(let a): "activity.\(a.kindKey)"
        case .mediaAndActivity(let a): "media+\(a.kindKey)"
        }
    }

    var activity: NotchActivity? {
        switch self {
        case .media: nil
        case .activity(let a), .mediaAndActivity(let a): a
        }
    }

    static func isWideActivity(_ a: NotchActivity) -> Bool {
        switch a {
        case .timer, .highAlert, .recording, .screenRecording, .vpnSession, .eventCountdown: true
        default: false
        }
    }

    static func pick(media: Bool, activity: NotchActivity?) -> WideIslandContent? {
        let eligible = activity.flatMap { isWideActivity($0) ? $0 : nil }
        switch (media, eligible) {
        case (true, let a?): return .mediaAndActivity(a)
        case (true, nil): return .media
        case (false, let a?): return .activity(a)
        case (false, nil): return nil
        }
    }
}
