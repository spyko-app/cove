import ColorSync
import CoreGraphics

/// Identidade persistente de um display (UUID via `CGDisplayCreateUUIDFromDisplayID`),
/// que sobrevive a plug/unplug e reordenação — nunca index ou "builtin vs external" (Droppy #12).
struct DisplayIdentity: Hashable, Codable {
    let uuid: String

    /// Constrói a identidade a partir de um `CGDirectDisplayID`. Chame do main
    /// actor (a API CoreGraphics de UUID é thread-safe, mas o id costuma vir
    /// de código de UI já no main thread).
    static func current(for id: CGDirectDisplayID) -> DisplayIdentity {
        if let ref = CGDisplayCreateUUIDFromDisplayID(id) {
            let cfUUID = ref.takeRetainedValue()
            let str = CFUUIDCreateString(nil, cfUUID) as String? ?? "id-\(id)"
            return DisplayIdentity(uuid: str)
        }
        return DisplayIdentity(uuid: "id-\(id)")
    }
}

/// Regra pura: decide se o painel deve aparecer num display, dado overrides
/// por identidade persistente e o modo global (all|builtin|external).
enum DisplayPolicy {
    static func wantsPanel(uuid: String, isBuiltin: Bool, global: String, overrides: [String: Bool]) -> Bool {
        if let override = overrides[uuid] {
            return override
        }
        switch global {
        case "builtin": return isBuiltin
        case "external": return !isBuiltin
        default: return true
        }
    }

    /// True se pelo menos uma tela ficaria com a ilha, dada a combinação
    /// atual de `global`/`overrides` — usado pra avisar em Ajustes quando a
    /// combinação escolhida esconde a ilha em todo display (item 6 da auditoria).
    static func anyVisible(screens: [(uuid: String, isBuiltin: Bool)], global: String, overrides: [String: Bool]) -> Bool {
        screens.contains { wantsPanel(uuid: $0.uuid, isBuiltin: $0.isBuiltin, global: global, overrides: overrides) }
    }
}
