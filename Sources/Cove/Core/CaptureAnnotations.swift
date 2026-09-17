import CoreGraphics
import Foundation

enum AnnotationTool: String, Codable, CaseIterable {
    case arrow
    case rect
    case blur
    case badge
}

struct Annotation: Identifiable, Equatable {
    let id: UUID
    var tool: AnnotationTool
    var from: CGPoint
    var to: CGPoint
    var number: Int?
    var color: String

    init(id: UUID = UUID(), tool: AnnotationTool, from: CGPoint, to: CGPoint, number: Int? = nil, color: String) {
        self.id = id
        self.tool = tool
        self.from = from
        self.to = to
        self.number = number
        self.color = color
    }
}

enum BackgroundStyle: Equatable {
    case none
    case solid(String)
    case gradient(String)
}

struct AnnotationDocument: Equatable {
    var annotations: [Annotation] = []
    var background: BackgroundStyle = .none
    var padding: CGFloat = 0

    mutating func add(tool: AnnotationTool, from: CGPoint, to: CGPoint, color: String) {
        var number: Int?
        if tool == .badge {
            number = annotations.filter { $0.tool == .badge }.count + 1
        }
        annotations.append(Annotation(tool: tool, from: from, to: to, number: number, color: color))
    }

    @discardableResult
    mutating func undo() -> Annotation? {
        guard let removed = annotations.popLast() else { return nil }
        renumberBadges()
        return removed
    }

    mutating func clear() {
        annotations.removeAll()
    }

    private mutating func renumberBadges() {
        var n = 1
        for i in annotations.indices where annotations[i].tool == .badge {
            annotations[i].number = n
            n += 1
        }
    }

    static func strokeScale(exportWidth: CGFloat, previewWidth: CGFloat) -> CGFloat {
        guard previewWidth > 0 else { return 1 }
        return max(exportWidth / previewWidth, 1)
    }
}

enum ExportNaming {
    static func uniqueExportName(base: String, existing: (String) -> Bool) -> String {
        let plain = "\(base)-editado.png"
        if !existing(plain) { return plain }
        var n = 2
        while true {
            let candidate = "\(base)-editado-\(n).png"
            if !existing(candidate) { return candidate }
            n += 1
        }
    }
}
