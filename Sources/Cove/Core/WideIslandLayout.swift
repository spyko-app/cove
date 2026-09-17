import Foundation

/// Quando a ilha FECHADA adota o "estilo largo" — espelha o
/// `isDynamicIslandLimitedInWidth == false` do iOS 27: havendo largura
/// sobrando (tela sem notch físico), mostra informação em vez de só as asas.
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

/// Regra pura da ilha larga (sem SwiftUI, testável).
enum WideIslandLayout {
    /// Largura extra da ilha fechada no estilo largo.
    static let extraWidth: CGFloat = 120

    /// `simulated` = cápsula simulada (tela sem notch físico).
    static func isWide(mode: WideIslandMode, simulated: Bool) -> Bool {
        switch mode {
        case .off: false
        case .externalOnly: simulated
        case .always: true
        }
    }

    /// Rótulo curto da atividade no estilo largo (§7 da ILHA-SPEC).
    /// Difere de `ActivityExpansion.regions().title` onde o card expandido é
    /// mais verboso (ex.: "VPN conectada" → "VPN").
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

/// O que a ilha larga mostra quando fechada. `nil` = largura normal.
enum WideIslandContent: Equatable {
    /// Só mídia: `MediaWings(titled: true)` (título + artista).
    case media
    /// Só atividade: ícone + rótulo à esquerda, valor à direita.
    case activity(NotchActivity)
    /// Mídia E atividade: a atividade (o que muda) à direita, arte à esquerda.
    case mediaAndActivity(NotchActivity)

    /// Chave ESTÁVEL pra animar a largura: o payload (`mm:ss`) muda a cada
    /// segundo e re-dispararia o spring a cada tick.
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

    /// Atividades persistentes que merecem a ilha larga (as do `ambientActivity`).
    static func isWideActivity(_ a: NotchActivity) -> Bool {
        switch a {
        case .timer, .highAlert, .recording, .screenRecording, .vpnSession, .eventCountdown: true
        default: false
        }
    }

    /// Seletor de conteúdo: sem mídia e sem atividade elegível → `nil`.
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
