import ColorSync
import CoreGraphics

struct DisplayIdentity: Hashable, Codable {
    let uuid: String

    static func current(for id: CGDirectDisplayID) -> DisplayIdentity {
        if let ref = CGDisplayCreateUUIDFromDisplayID(id) {
            let cfUUID = ref.takeRetainedValue()
            let str = CFUUIDCreateString(nil, cfUUID) as String? ?? "id-\(id)"
            return DisplayIdentity(uuid: str)
        }
        return DisplayIdentity(uuid: "id-\(id)")
    }
}

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

    static func anyVisible(screens: [(uuid: String, isBuiltin: Bool)], global: String, overrides: [String: Bool]) -> Bool {
        screens.contains { wantsPanel(uuid: $0.uuid, isBuiltin: $0.isBuiltin, global: global, overrides: overrides) }
    }
}
