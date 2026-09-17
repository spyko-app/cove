import SwiftUI

/// "Aurora" atrás do card de mídia expandido: 3-4 gradientes radiais suaves
/// que respiram com o áudio (`WaveformService.levels`). Puramente decorativo
/// — nunca captura toque, nunca compete com o texto por cima (opacidade baixa
/// + blend `.plusLighter`).
struct MotionArtView: View {
    @ObservedObject var waveform: WaveformService
    var tint: Color = .white.opacity(0.3)
    var running: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var smoothed: [Float] = Array(repeating: 0, count: 5)

    private let blobOffsets: [(CGFloat, CGFloat)] = [(-0.3, -0.4), (0.35, -0.2), (-0.15, 0.35), (0.3, 0.4)]

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, size in
                    draw(context: &context, size: size, levels: [0.4, 0.5, 0.6, 0.5, 0.4])
                }
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !running)) { _ in
                    Canvas { context, size in
                        draw(context: &context, size: size, levels: smoothed)
                    }
                    .onChange(of: waveform.levels) { _, next in
                        smoothed = MotionMath.smooth(prev: smoothed, next: next, alpha: 0.25)
                    }
                }
            }
        }
        .blendMode(.plusLighter)
        .opacity(0.35)
        .allowsHitTesting(false)
    }

    private func draw(context: inout GraphicsContext, size: CGSize, levels: [Float]) {
        let energy = CGFloat(MotionMath.energy(levels))
        let baseRadius = min(size.width, size.height) * (0.35 + energy * 0.25)
        let color = tint

        for (i, offset) in blobOffsets.enumerated() {
            let level = CGFloat(i < levels.count ? levels[i] : levels.first ?? 0)
            let center = CGPoint(x: size.width / 2 + offset.0 * size.width,
                                  y: size.height / 2 + offset.1 * size.height)
            let radius = baseRadius * (0.7 + level * 0.6)
            let gradient = Gradient(colors: [color.opacity(0.9), color.opacity(0)])
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2)),
                with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))
        }
    }
}
