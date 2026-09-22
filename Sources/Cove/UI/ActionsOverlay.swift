import AppKit
import SwiftUI

struct ActionsOverlay: View {
    @ObservedObject var coordinator: NotchCoordinator
    let notchTop: CGFloat

    private var actions: [RingAction] { RingAction.normalize(coordinator.config.ringActions) }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: ActionsGrid.columns(for: actions.count))
    }

    var body: some View {
        VStack(spacing: 6) {
            Color.clear.frame(height: notchTop)
            header
            Group {
                #if compiler(>=6.2)
                if #available(macOS 26, *) {
                    GlassEffectContainer { grid }
                } else {
                    grid
                }
                #else
                grid
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .onExitCommand { close() }
    }

    private var header: some View {
        HStack {
            Text("Ações").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button("Editar…") {
                close()
                SettingsWindowManager.shared.show(coordinator: coordinator)
            }
            .buttonStyle(NotchButtonStyle())
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(actions) { action in
                ActionTile(action: action, coordinator: coordinator, onRun: close)
            }
        }
    }

    private func close() {
        coordinator.toggleActions()
    }
}

private struct ActionTile: View {
    let action: RingAction
    @ObservedObject var coordinator: NotchCoordinator
    let onRun: () -> Void

    var body: some View {
        Button {
            coordinator.perform(action)
            onRun()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(action.isMissing ? .orange : .white)
                Text(action.title)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .padding(5)
            .coveCardBackground(cornerRadius: 12)
        }
        .buttonStyle(CardButtonStyle())
        .onLongPressGesture(minimumDuration: 0.35) {
            guard case .capture = action else { return }
            popCaptureModeMenu(coordinator)
            onRun()
        }
        .help(action.title)
    }
}
