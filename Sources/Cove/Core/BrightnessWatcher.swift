import CoreGraphics
import Foundation

/// Observa o brilho do display interno (DisplayServices privado, mesmo padrão
/// dlopen do CoveDisplay) — alimenta o HUD de brilho. Poll leve (250ms, uma
/// chamada C) porque o callback de notificação do DS não é público.
@MainActor
final class BrightnessWatcher {
    var onBrightnessChange: ((Float) -> Void)?

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getBrightness: GetFn? = {
        guard let h = handle, let s = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(s, to: GetFn.self)
    }()

    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let setBrightnessFn: SetFn? = {
        guard let h = handle, let s = dlsym(h, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(s, to: SetFn.self)
    }()

    static func set(_ v: Float) {
        _ = setBrightnessFn?(CGMainDisplayID(), min(max(v, 0), 1))
    }

    private var last: Float = -1
    private var timer: Timer?

    /// Com o key tap ativo as teclas já reportam; poll só cobre mudanças
    /// externas (Central de Controle) — cadência cai de 250ms pra 1s.
    func setSlowMode(_ slow: Bool) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: slow ? 1.0 : 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    init() {
        guard Self.getBrightness != nil else { return }
        last = Self.read() ?? -1
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    static func read() -> Float? {
        var v: Float = 0
        guard getBrightness?(CGMainDisplayID(), &v) == 0 else { return nil }
        return v
    }

    private func tick() {
        guard let v = Self.read() else { return }
        // auto-brilho (sensor de luz) anda em passos ~1% — não é o usuário; tecla/slider = 6%+
        if last >= 0, abs(v - last) >= 0.03 {
            onBrightnessChange?(v)
        }
        last = v
    }
}
