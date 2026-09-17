import CoreGraphics
import Foundation

/// Ferramenta de anotação do editor de captura.
enum AnnotationTool: String, Codable, CaseIterable {
    case arrow
    case rect
    case blur
    case badge
}

/// Uma anotação desenhada sobre a captura.
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

/// Fundo aplicado atrás da captura no export.
enum BackgroundStyle: Equatable {
    case none
    case solid(String)
    case gradient(String)
}

/// Documento puro do editor: anotações + fundo + padding.
/// Numera badges automaticamente (1, 2, 3…) e renumera ao desfazer.
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

    /// Fator de escala pra traço/badge/seta ao renderizar em `exportWidth`
    /// (ex.: `image.size.width`) a partir do que foi desenhado numa prévia
    /// de `previewWidth`. Sempre ≥ 1 — a prévia nunca é maior que a export.
    static func strokeScale(exportWidth: CGFloat, previewWidth: CGFloat) -> CGFloat {
        guard previewWidth > 0 else { return 1 }
        return max(exportWidth / previewWidth, 1)
    }
}

/// Gera um nome de arquivo de export que não sobrescreve um já existente.
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
