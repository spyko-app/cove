import Foundation

enum HUDStyleResolver {
    static let validStyles: Set<String> = ["white", "accent", "glow"]

    static func style(for kind: String, styles: [String: String], fallback: String) -> String {
        if let override = styles[kind], validStyles.contains(override) {
            return override
        }
        return fallback
    }
}
