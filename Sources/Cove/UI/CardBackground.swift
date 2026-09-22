import SwiftUI

private struct DynamicGlassKey: EnvironmentKey {
    static let defaultValue = false
}

private struct DynamicGlassTintKey: EnvironmentKey {
    static let defaultValue = 0.55
}

extension EnvironmentValues {
    var dynamicGlass: Bool {
        get { self[DynamicGlassKey.self] }
        set { self[DynamicGlassKey.self] = newValue }
    }

    var dynamicGlassTint: Double {
        get { self[DynamicGlassTintKey.self] }
        set { self[DynamicGlassTintKey.self] = newValue }
    }
}

private struct CoveCardBackground: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.dynamicGlass) private var dynamicGlass
    @Environment(\.dynamicGlassTint) private var dynamicGlassTint
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), CardStyle.usesGlass(available: true, enabled: dynamicGlass, reduceTransparency: reduceTransparency) {
            let tint = min(1, max(0, dynamicGlassTint))
            content.glassEffect(
                .regular.tint(.black.opacity(tint * 0.6)),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .modifier(LayerSeparation(cornerRadius: cornerRadius))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white.opacity(0.08)))
    }
}

private struct LayerSeparation: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            shape
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                .background {
                    shape
                        .stroke(.black.opacity(0.35), lineWidth: 2)
                        .blur(radius: 2)
                        .mask(shape)
                }
                .allowsHitTesting(false)
        }
    }
}

extension View {
    func coveCardBackground(cornerRadius: CGFloat) -> some View {
        modifier(CoveCardBackground(cornerRadius: cornerRadius))
    }
}

enum CardStyle {
    static func usesGlass(available: Bool, enabled: Bool, reduceTransparency: Bool) -> Bool {
        available && enabled && !reduceTransparency
    }
}
