import AppKit
import SwiftUI

/// Vista expandida da atividade (F1/F2 do ciclo 8) — espelha as 4 regiões da
/// Live Activity do iOS 27 DENTRO da ilha aberta, sem PageBar:
/// leading = ícone do tipo · center = título + subtítulo · trailing = valor
/// grande tabular · bottom = chips-cápsula de ação (`LiveActivityIntent`).
struct ActivityExpandedView: View {
    @ObservedObject var coordinator: NotchCoordinator
    let activity: NotchActivity
    let notchTop: CGFloat

    /// Relógio de 1s só pra o valor tabular andar (timer, countdown, sessão).
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var regions: ActivityExpansion.Regions {
        ActivityExpansion.regions(for: activity, context: coordinator.expansionContext(now: now))
    }

    var body: some View {
        let r = regions
        VStack(spacing: 0) {
            Color.clear.frame(height: notchTop)
            HStack(alignment: .center, spacing: 12) {
                // leading — ícone do tipo (cores da §7 da ILHA-SPEC)
                Image(systemName: r.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color(r.tint))
                    .frame(width: 28)

                // center — título + subtítulo
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !r.subtitle.isEmpty {
                        Text(r.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // trailing — valor grande tabular (ou o anel do countdown)
                if case .eventCountdown(_, let start, _) = activity {
                    CountdownRing(progress: NotchActivity.eventCountdownProgress(now: now, start: start))
                } else if let value = r.value {
                    Text(value)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(color(r.tint))
                        .lineLimit(1).fixedSize()
                }
            }
            .frame(maxHeight: .infinity)

            // bottom — ações rápidas
            if !r.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(r.actions) { a in
                        ActivityChip(title: a.title, symbol: a.symbol) {
                            coordinator.perform(a.action)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 10)
            }
        }
        .onReceive(clock) { now = $0 }
        .onHover { over in
            // hover no card segura o fechamento automático de 6 s
            if over { coordinator.cancelActivityExpandedDismiss() } else { coordinator.armActivityExpandedDismiss() }
        }
        // Esc só chega com o painel key (I1). Foco de teclado só quando o
        // dono abriu no gesto — alerta automático nunca rouba o teclado.
        .onAppear { if coordinator.activityExpandedFromGesture { NotchPanelController.current?.makeKey() } }
        .onDisappear { if coordinator.activityExpandedFromGesture { NotchPanelController.current?.resignKey() } }
        .onExitCommand { coordinator.closeActivityExpanded() }
    }

    private func color(_ t: ActivityExpansion.Tint) -> Color {
        switch t {
        case .white: .white
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .purple: .purple
        case .gray: .white.opacity(0.45)
        }
    }
}

/// Anel do countdown de evento, no tamanho da região trailing.
private struct CountdownRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, min(progress, 1)))
                .stroke(.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
        .animation(.snappy(duration: 0.18), value: progress)
    }
}

/// Chip-cápsula da região bottom — mesma anatomia do `ToolChip` de Ferramentas
/// (9 pt medium, padding 5/2, `white .10` → `.18` no hover).
private struct ActivityChip: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var over = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                Text(title)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
        }
        .buttonStyle(ActivityChipStyle(over: $over))
    }
}

private struct ActivityChipStyle: ButtonStyle {
    @Binding var over: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule())
            .background(Capsule().fill(.white.opacity(over ? 0.18 : 0.10)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.smooth(duration: 0.14), value: over)
            .animation(.spring(duration: 0.14, bounce: 0.25), value: configuration.isPressed)
            .onHover { o in
                guard o != over else { return }
                over = o
            }
    }
}
