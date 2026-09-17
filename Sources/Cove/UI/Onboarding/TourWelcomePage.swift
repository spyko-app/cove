import SwiftUI

struct TourWelcomePage: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "capsule.fill")
                .font(.system(size: 56))
                .foregroundStyle(.primary)
                .padding(.top, 12)
            Text("Bem-vindo ao Cove").font(.title.bold())
            Text("A área do notch vira uma Dynamic Island: mídia, atalhos e ferramentas a um clique, sem sair do que você está fazendo.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            Spacer()
        }
        .padding(24)
    }
}
