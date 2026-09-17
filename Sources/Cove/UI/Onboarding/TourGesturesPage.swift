import SwiftUI

struct TourGesturesPage: View {
    @State private var scrollDown = false
    @State private var sidePan: CGFloat = 0

    var body: some View {
        VStack(spacing: 22) {
            Text("Gestos").font(.title2.bold()).padding(.top, 12)

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                    .offset(y: scrollDown ? 10 : 0)
                    .opacity(scrollDown ? 0.5 : 1)
                Text("Role para baixo na ilha para abrir")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                HStack(spacing: 24) {
                    Image(systemName: "arrow.left.circle.fill").font(.system(size: 28)).foregroundStyle(.purple)
                        .offset(x: sidePan)
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 28)).foregroundStyle(.purple)
                        .offset(x: sidePan)
                }
                Text("Arraste pros lados para trocar faixa ou de página")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(24)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                scrollDown = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                sidePan = 6
            }
        }
    }
}
