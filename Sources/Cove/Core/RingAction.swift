import AppKit
import Foundation

extension ScreenCapture.Mode: Codable {
    private enum Kind: String, Codable { case region, window, fullScreen, timer }
    private struct Box: Codable { var kind: Kind; var seconds: Int? }

    public init(from decoder: Decoder) throws {
        let box = try Box(from: decoder)
        switch box.kind {
        case .region: self = .region
        case .window: self = .window
        case .fullScreen: self = .fullScreen
        case .timer: self = .timer(seconds: box.seconds ?? 5)
        }
    }

    public func encode(to encoder: Encoder) throws {
        let box: Box
        switch self {
        case .region: box = Box(kind: .region, seconds: nil)
        case .window: box = Box(kind: .window, seconds: nil)
        case .fullScreen: box = Box(kind: .fullScreen, seconds: nil)
        case .timer(let seconds): box = Box(kind: .timer, seconds: seconds)
        }
        try box.encode(to: encoder)
    }
}

enum RingAction: Codable, Equatable, Identifiable {
    case droplet(Droplet)
    case capture(ScreenCapture.Mode?)
    case ocr
    case color
    case screenRecord
    case pomodoro
    case highAlert
    case app(bundleID: String)
    case shortcut(name: String)

    var id: String {
        switch self {
        case .droplet(let d): "droplet:\(d.rawValue)"
        case .capture: "capture"
        case .ocr: "ocr"
        case .color: "color"
        case .screenRecord: "screenRecord"
        case .pomodoro: "pomodoro"
        case .highAlert: "highAlert"
        case .app(let bundleID): "app:\(bundleID)"
        case .shortcut(let name): "shortcut:\(name)"
        }
    }

    var title: String {
        switch self {
        case .droplet(let d): d.title
        case .capture: "Capturar"
        case .ocr: "OCR"
        case .color: "Cor"
        case .screenRecord: "Gravar tela"
        case .pomodoro: "Pomodoro"
        case .highAlert: "High Alert"
        case .app(let bundleID):
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { $0.deletingPathExtension().lastPathComponent } ?? bundleID
        case .shortcut(let name): name
        }
    }

    var symbol: String {
        switch self {
        case .droplet(let d): d.symbol
        case .capture: "camera.viewfinder"
        case .ocr: "text.viewfinder"
        case .color: "eyedropper"
        case .screenRecord: "record.circle"
        case .pomodoro: "timer"
        case .highAlert: "bolt.fill"
        case .app(let bundleID):
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
                ? "app.badge" : "exclamationmark.triangle"
        case .shortcut: "square.stack.3d.up.badge.a"
        }
    }

    var isMissing: Bool {
        if case .app(let bundleID) = self {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil
        }
        return false
    }

    static let defaults: [RingAction] = [
        .capture(nil), .ocr, .droplet(.clipboard), .droplet(.shelf), .pomodoro, .highAlert,
    ]

    static func normalize(_ actions: [RingAction]) -> [RingAction] {
        var seen = Set<String>()
        var out: [RingAction] = []
        for action in actions where seen.insert(action.id).inserted {
            out.append(action)
        }
        if out.count < 2 { return defaults }
        if out.count > 8 { out = Array(out.prefix(8)) }
        return out
    }

    private enum CodingKeys: String, CodingKey { case type, value, seconds }

    private enum Tag: String, Codable {
        case droplet, capture, ocr, color, screenRecord, pomodoro, highAlert, app, shortcut
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(Tag.self, forKey: .type)
        switch tag {
        case .droplet:
            let raw = try c.decode(String.self, forKey: .value)
            guard let d = Droplet(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value, in: c, debugDescription: "droplet desconhecido: \(raw)")
            }
            self = .droplet(d)
        case .capture:
            self = .capture(try c.decodeIfPresent(ScreenCapture.Mode.self, forKey: .value))
        case .ocr: self = .ocr
        case .color: self = .color
        case .screenRecord: self = .screenRecord
        case .pomodoro: self = .pomodoro
        case .highAlert: self = .highAlert
        case .app: self = .app(bundleID: try c.decode(String.self, forKey: .value))
        case .shortcut: self = .shortcut(name: try c.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .droplet(let d):
            try c.encode(Tag.droplet, forKey: .type)
            try c.encode(d.rawValue, forKey: .value)
        case .capture(let mode):
            try c.encode(Tag.capture, forKey: .type)
            try c.encodeIfPresent(mode, forKey: .value)
        case .ocr: try c.encode(Tag.ocr, forKey: .type)
        case .color: try c.encode(Tag.color, forKey: .type)
        case .screenRecord: try c.encode(Tag.screenRecord, forKey: .type)
        case .pomodoro: try c.encode(Tag.pomodoro, forKey: .type)
        case .highAlert: try c.encode(Tag.highAlert, forKey: .type)
        case .app(let bundleID):
            try c.encode(Tag.app, forKey: .type)
            try c.encode(bundleID, forKey: .value)
        case .shortcut(let name):
            try c.encode(Tag.shortcut, forKey: .type)
            try c.encode(name, forKey: .value)
        }
    }
}

enum RingActionListCoding {
    private struct AnyDecodableBox: Decodable {
        let action: RingAction?
        init(from decoder: Decoder) throws {
            action = try? RingAction(from: decoder)
        }
    }

    static func decode(_ container: inout UnkeyedDecodingContainer) throws -> [RingAction] {
        var out: [RingAction] = []
        while !container.isAtEnd {
            if let box = try? container.decode(AnyDecodableBox.self), let action = box.action {
                out.append(action)
            }
        }
        return out
    }
}

extension RingAction {
    static func decodeTolerantList(_ data: Data) throws -> [RingAction] {
        struct Wrapper: Decodable {
            let items: [RingAction]
            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                items = try RingActionListCoding.decode(&container)
            }
        }
        return try JSONDecoder().decode(Wrapper.self, from: data).items
    }
}
