import SwiftUI

/// Flag "Dynamic Glass" (macOS 26+) propagada via ambiente, lida em `NotchView` a partir de
/// `coordinator.config.dynamicGlass`. OFF por padrão: com vidro e halo a ilha parecia
/// uma tela acesa (dono, 12/set). O vidro é opt-in e só nos cards internos.
private struct DynamicGlassKey: EnvironmentKey {
    static let defaultValue = false
}

/// Intensidade do vidro (0 = ultraclaro, 1 = tingido), de `config.dynamicGlassTint`.
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
        if #available(macOS 26, *), CardStyle.usesGlass(available: true, enabled: dynamicGlass, reduceTransparency: reduceTransparency) {
            let tint = min(1, max(0, dynamicGlassTint))
            content.glassEffect(
// 0.6: o extremo "Tingido" escurece sem virar card preto opaco (o vidro tem que continuar vidro)
                .regular.tint(.black.opacity(tint * 0.6)),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .modifier(LayerSeparation(cornerRadius: cornerRadius))
        } else {
            content
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(0.08)))   // visual aprovado: preto puro + card .08, sem borda nem halo
        }
    }
}

/// "More separation between glass layers" (iOS 27): borda branca .12 de 0,5 pt +
/// sombra interna sutil, pra o card destacar do vidro atrás sem virar contorno duro.
/// `strokeBorder` inseta pra dentro — o raio da spec fica intacto.
private struct LayerSeparation: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            shape
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                .background {
                    // sombra interna: anel escuro difuso colado na borda, recortado pela forma
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
    /// Fundo padrão dos cards da ilha expandida: Liquid Glass opcional (macOS 26+, flag
    /// `dynamicGlass` ligada, sem "reduzir transparência"), senão o preenchimento atual.
    func coveCardBackground(cornerRadius: CGFloat) -> some View {
        modifier(CoveCardBackground(cornerRadius: cornerRadius))
    }
}

/// Regra pura: quando usar o efeito de vidro nos cards internos.
enum CardStyle {
    static func usesGlass(available: Bool, enabled: Bool, reduceTransparency: Bool) -> Bool {
        available && enabled && !reduceTransparency
    }
}
