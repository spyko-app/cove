import AppKit

// NX key codes (fora da classe: callback C não pode capturar Self dinâmico)
private let kSoundUp = 0, kSoundDown = 1, kBrightnessUp = 2, kBrightnessDown = 3, kMute = 7
private let kIllumUp = 21, kIllumDown = 22
import CoreGraphics
import Foundation

/// Intercepta as TECLAS de volume/brilho (CGEventTap em NX_SYSDEFINED) e
/// consome o evento — o sistema nunca vê a tecla, então o HUD nativo (Dock no
/// macOS 26; OSDUIHelper congelado cobre o legado) nunca nasce. Nós aplicamos
/// o ajuste e a ilha mostra o HUD. Exige Acessibilidade (prompt único);
/// sem permissão, degrada: teclas seguem pro sistema.
@MainActor
final class MediaKeyTap {
    var onVolumeKey: ((_ delta: Int, _ mute: Bool) -> Void)?
    var onBrightnessKey: ((_ delta: Int) -> Void)?
    /// Retorna false se não quiser consumir (sem backlight controlável).
    var onKeyboardBrightnessKey: ((_ delta: Int) -> Bool)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var active = false
    /// último key-down foi consumido? (key-up segue o mesmo destino)
    fileprivate var lastConsumed = true

    private static var promptedOnce = false

    /// `prompt` só em ação do usuário (onboarding, toggle nos Ajustes). No
    /// launch nunca pergunta: assinatura ad-hoc muda a cada build e o macOS
    /// re-pediria toda vez — sem permissão, degrada em silêncio.
    func start(prompt: Bool = false) {
        guard !active else { return }
        let trusted: Bool
        if prompt, !Self.promptedOnce {
            Self.promptedOnce = true
            trusted = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        } else {
            trusted = AXIsProcessTrusted()
        }
        FileHandle.standardError.write("[keytap] start prompt=\(prompt) trusted=\(trusted)\n".data(using: .utf8)!)
        guard trusted else { return }

        let mask = CGEventMask(1 << NX_SYSDEFINED)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8
            else { return Unmanaged.passUnretained(event) }
            let data = nsEvent.data1
            let keyCode = (data & 0xFFFF_0000) >> 16
            let keyFlags = data & 0x0000_FFFF
            let pressed = ((keyFlags & 0xFF00) >> 8) == 0x0A
            guard pressed else {
                // key-up dos códigos que tratamos também morre (senão vaza)
                return [kSoundUp, kSoundDown, kMute, kBrightnessUp, kBrightnessDown,
                        kIllumUp, kIllumDown].contains(keyCode) && me.lastConsumed
                    ? nil : Unmanaged.passUnretained(event)
            }
            me.lastConsumed = true
            switch keyCode {
            case kIllumUp, kIllumDown:
                // backlight só se KeyboardBacklight responder; senão deixa passar
                guard let h = me.onKeyboardBrightnessKey else { return Unmanaged.passUnretained(event) }
                let consumed = MainActor.assumeIsolated { h(keyCode == kIllumUp ? +1 : -1) }
                me.lastConsumed = consumed
                return consumed ? nil : Unmanaged.passUnretained(event)
            case kSoundUp: Task { @MainActor in me.onVolumeKey?(+1, false) }
            case kSoundDown: Task { @MainActor in me.onVolumeKey?(-1, false) }
            case kMute: Task { @MainActor in me.onVolumeKey?(0, true) }
            case kBrightnessUp: Task { @MainActor in me.onBrightnessKey?(+1) }
            case kBrightnessDown: Task { @MainActor in me.onBrightnessKey?(-1) }
            default: return Unmanaged.passUnretained(event)
            }
            return nil  // consumido — HUD nativo nunca dispara
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { FileHandle.standardError.write("[keytap] tapCreate FALHOU\n".data(using: .utf8)!); return }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        active = true
        FileHandle.standardError.write("[keytap] ATIVO\n".data(using: .utf8)!)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil
        runLoopSource = nil
        active = false
    }
}
