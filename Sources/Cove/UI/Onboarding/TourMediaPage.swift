import SwiftUI

/// Demo ao vivo: expande a ilha de verdade enquanto a página está visível.
struct TourMediaPage: View {
    @ObservedObject var coordinator: NotchCoordinator

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note")
                .font(.system(size: 44))
                .foregroundStyle(.pink)
                .padding(.top, 12)
            Text("Mídia ao vivo").font(.title2.bold())
            Text("Toque algo em qualquer app e a ilha mostra capa, faixa e controles — olhe agora no topo da tela.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            Spacer()
        }
        .padding(24)
        .onAppear {
            let hasMedia = !coordinator.media.nowPlaying.title.isEmpty
            let pages = Droplet.pages(enabled: coordinator.config.enabledDroplets, hasMedia: hasMedia)
            if hasMedia, pages.contains(.media) {
                coordinator.requestShowDroplet(.media)
            } else {
                coordinator.requestExpand(true)
            }
        }
        .onDisappear { coordinator.requestExpand(false) }
    }
}
