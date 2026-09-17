import Foundation

/// Backlight do teclado via CoreBrightness privado (KeyboardBrightnessClient).
/// Mesmo padrão dlopen + NSClassFromString dos outros serviços; sem a classe,
/// `available == false` e as teclas F5/F6 seguem pro sistema.
@MainActor
final class KeyboardBacklight {
    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
    private let client: AnyObject?
    private let keyboardID: UInt64 = 1

    var available: Bool { client != nil }

    init() {
        guard Self.handle != nil, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { client = nil; return }
        client = cls.init()
    }

    var brightness: Float {
        guard let client,
              client.responds(to: NSSelectorFromString("brightnessForKeyboard:")) else { return 0 }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt64) -> Float
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        let imp = unsafeBitCast(client.method(for: sel), to: Fn.self)
        return imp(client, sel, keyboardID)
    }

    @discardableResult
    func set(_ value: Float) -> Bool {
        guard let client,
              client.responds(to: NSSelectorFromString("setBrightness:forKeyboard:")) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        let imp = unsafeBitCast(client.method(for: sel), to: Fn.self)
        return imp(client, sel, min(max(value, 0), 1), keyboardID)
    }
}
