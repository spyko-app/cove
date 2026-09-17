import SwiftUI

struct TourDropletsPage: View {
    @ObservedObject var coordinator: NotchCoordinator

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        VStack(spacing: 14) {
            Text("Droplets").font(.title2.bold()).padding(.top, 12)
            Text("Cada droplet é uma página da ilha. Ligue as que quiser — dá pra mudar depois nas Configurações.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Droplet.allCases.filter { $0 != .media }, id: \.self) { droplet in
                        let isEnabled = coordinator.config.enabledDroplets.contains(droplet.rawValue)
                        let isLastEnabled = isEnabled && coordinator.config.enabledDroplets.count == 1
                        DropletToggle(
                            droplet: droplet,
                            enabled: isEnabled,
                            disabled: isLastEnabled
                        ) {
                            coordinator.updateConfig { config in
                                if let idx = config.enabledDroplets.firstIndex(of: droplet.rawValue) {
                                    guard config.enabledDroplets.count > 1 else { return }
                                    config.enabledDroplets.remove(at: idx)
                                } else {
                                    config.enabledDroplets.append(droplet.rawValue)
                                }
                            }
                        }
                        .help(isLastEnabled ? "Pelo menos um droplet" : "")
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 260)
            Spacer()
        }
        .padding(24)
    }
}

private struct DropletToggle: View {
    let droplet: Droplet
    let enabled: Bool
    var disabled: Bool = false
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 6) {
                Image(systemName: droplet.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(enabled ? .white : .secondary)
                    .frame(width: 44, height: 44)
                    .background(enabled ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary.opacity(0.4)),
                                in: RoundedRectangle(cornerRadius: 10))
                Text(droplet.title).font(.caption).foregroundStyle(.primary)
            }
            .opacity(disabled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
