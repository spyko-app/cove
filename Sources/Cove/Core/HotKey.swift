import Carbon

struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    private static let keys: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
        "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "space": 49, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    static func parse(_ s: String) -> HotKeyCombo? {
        var mods: UInt32 = 0
        var key: UInt32?
        for part in s.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "ctrl", "control": mods |= UInt32(controlKey)
            case "opt", "alt", "option": mods |= UInt32(optionKey)
            case "cmd", "command": mods |= UInt32(cmdKey)
            case "shift": mods |= UInt32(shiftKey)
            default: key = keys[part]
            }
        }
        guard let key, mods != 0 else { return nil }
        return HotKeyCombo(keyCode: key, modifiers: mods)
    }
}

/// Uma tabela de conflito é útil pra planejar registros antes de mexer no
/// Carbon de verdade — pura, sem side effect, fácil de testar.
enum HotKeyRegistryPlanner {
    static func conflicts(in pairs: [(id: UInt32, combo: HotKeyCombo)]) -> [HotKeyCombo] {
        var counts: [HotKeyCombo: Int] = [:]
        for (_, combo) in pairs { counts[combo, default: 0] += 1 }
        return counts.filter { $0.value > 1 }.map(\.key)
    }
}

extension HotKeyCombo: Hashable {}

/// Hotkeys globais via Carbon — não exige Acessibilidade. UM handler Carbon
/// só, ids despachados pro handler registrado (Ring = 1, droplets = 100+).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private static let signature: OSType = 0x53_50_59_4B  // 'SPYK'

    private init() {}

    @discardableResult
    func register(id: UInt32, combo: HotKeyCombo, handler: @escaping () -> Void) -> Bool {
        unregister(id: id)
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        handlers[id] = handler
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs[id] = nil
        handlers[id] = nil
    }

    func unregisterAll() {
        for id in Array(refs.keys) { unregister(id: id) }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            Task { @MainActor in center.handlers[id]?() }
            return noErr
        }, 1, &spec, me, &eventHandlerRef)
    }

    deinit {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}
