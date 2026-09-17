import CoreGraphics

/// Assinatura pura da configuração de telas (id + frame + notch), usada pra
/// decidir se um `reload()` de fato precisa reconstruir os painéis.
enum ScreenSignature {
    static func make(_ screens: [(id: UInt32, frame: CGRect, notch: CGRect?)]) -> String {
        screens
            .sorted { $0.id < $1.id }
            .map { s in
                let f = s.frame
                let notchPart = s.notch.map { n in "\(Int(n.origin.x)),\(Int(n.origin.y)),\(Int(n.width)),\(Int(n.height))" } ?? "nil"
                return "\(s.id):\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height))|\(notchPart)"
            }
            .joined(separator: ";")
    }
}
