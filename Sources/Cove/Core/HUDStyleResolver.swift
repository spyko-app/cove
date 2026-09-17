import Foundation

/// Resolve o estilo visual de um HUD (white | accent | glow), permitindo
/// override por tipo (`kindKey`) sobre o estilo global. Puro — sem estado.
enum HUDStyleResolver {
    static let validStyles: Set<String> = ["white", "accent", "glow"]

    static func style(for kind: String, styles: [String: String], fallback: String) -> String {
        if let override = styles[kind], validStyles.contains(override) {
            return override
        }
        return fallback
    }
}
