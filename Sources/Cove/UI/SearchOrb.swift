import SwiftUI

struct SearchOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false
    @State private var dim = false

    static let size: CGFloat = 16
    private static let turn: Double = 2.4

    private var gradient: AngularGradient {
        AngularGradient(
            colors: [
                .white.opacity(0.95),
                Color(red: 0x0A / 255, green: 0x84 / 255, blue: 1).opacity(0.75),
                .white.opacity(0.35),
                .white.opacity(0.9),
            ],
            center: .center)
    }

    var body: some View {
        Circle()
            .strokeBorder(gradient, lineWidth: 2)
            .frame(width: Self.size, height: Self.size)
            .rotationEffect(.degrees(reduceMotion ? 0 : (spinning ? 360 : 0)))
            .opacity(reduceMotion ? (dim ? 0.45 : 1) : 1)
            .accessibilityLabel("Buscando")
            .onAppear {
                if reduceMotion {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
                } else {
                    withAnimation(.linear(duration: Self.turn).repeatForever(autoreverses: false)) { spinning = true }
                }
            }
    }
}
