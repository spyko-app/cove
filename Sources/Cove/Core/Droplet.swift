import Foundation

enum Droplet: String, CaseIterable, Codable {
    case media, apps, shelf, clipboard, tools, search, terminal, notifications, stats, notes, converter, emoji

    var title: String {
        switch self {
        case .media: "Mídia"; case .apps: "Apps"; case .shelf: "Cesta"
        case .clipboard: "Clipboard"; case .tools: "Ferramentas"; case .search: "Busca"; case .terminal: "Terminal"
        case .notifications: "Notificações"
        case .stats: "Sistema"
        case .notes: "Notas"
        case .converter: "Converter"
        case .emoji: "Emoji"
        }
    }
    var symbol: String {
        switch self {
        case .media: "music.note"; case .apps: "square.grid.2x2"; case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"; case .tools: "timer"; case .search: "magnifyingglass"; case .terminal: "terminal"
        case .notifications: "bell.badge"
        case .stats: "gauge.with.dots.needle.33percent"
        case .notes: "note.text"
        case .converter: "arrow.triangle.2.circlepath"
        case .emoji: "face.smiling"
        }
    }

    var scrollsInternally: Bool {
        switch self {
        case .shelf, .clipboard, .search, .terminal, .notifications: true
        case .media, .apps, .tools, .stats: false
        case .notes: true
        case .converter: true
        case .emoji: true
        }
    }

    static func pages(enabled: [String], hasMedia: Bool) -> [Droplet] {
        var out = enabled.compactMap(Droplet.init(rawValue:)).filter { $0 != .media }
        if out.isEmpty { out = [.apps] }
        return hasMedia ? [.media] + out : out
    }
}
