import AppKit
import SwiftUI

struct TourPermissionsPage: View {
    @ObservedObject var coordinator: NotchCoordinator
    @ObservedObject var state: PermissionState

    private var summary: String {
        PermissionState.summary([
            "accessibility": state.accessibility,
            "calendar": state.calendar,
            "screenRecording": state.screenRecording,
            "microphone": state.microphone,
            "speech": state.speech,
            "notifications": state.notifications,
        ])
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("Permissões").font(.title2.bold()).padding(.top, 12)
            Text("Todas são opcionais — sem elas o app funciona igual, só sem a feature correspondente. Cada uma também é pedida sozinha na primeira vez que você usa a feature.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
            Text(summary).font(.caption).foregroundStyle(.secondary)

            VStack(spacing: 10) {
                PermissionRow(icon: "keyboard", tint: .blue, title: "Acessibilidade",
                              subtitle: "Substituir o HUD de volume/brilho pela ilha", granted: state.accessibility) {
                    coordinator.startKeyTap(prompt: true)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        await state.refresh(notificationsAvailable: coordinator.notifications.available)
                    }
                }
                PermissionRow(icon: "calendar", tint: .red, title: "Calendário",
                              subtitle: "Próximo evento e aviso de hora de sair", granted: state.calendar) {
                    Task { @MainActor in
                        await coordinator.calendar.requestAccessIfNeeded()
                        await state.refresh(notificationsAvailable: coordinator.notifications.available)
                    }
                }
                PermissionRow(icon: "waveform", tint: .purple, title: "Captura de áudio",
                              subtitle: "Waveform ao vivo do que está tocando", granted: state.audioCapture) {
                    coordinator.waveform?.start()
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        state.audioCapture = coordinator.waveform?.running ?? false
                    }
                }
                PermissionRow(icon: "airpods", tint: .teal, title: "Bluetooth",
                              subtitle: "AirPods e fones: conexão e bateria na ilha", granted: state.bluetooth) {
                    coordinator.startBluetooth()
                    state.bluetooth = true
                }
                PermissionRow(icon: "mic.fill", tint: .orange, title: "Microfone",
                              subtitle: "Memos de voz — pedido ao gravar", granted: state.microphone) {
                    openPrivacyPane("Privacy_Microphone")
                }
                PermissionRow(icon: "waveform.and.mic", tint: .purple, title: "Reconhecimento de fala",
                              subtitle: "Memos de voz — pedido ao gravar", granted: state.speech) {
                    openPrivacyPane("Privacy_SpeechRecognition")
                }
                PermissionRow(icon: "rectangle.dashed.badge.record", tint: .red, title: "Gravação de Tela",
                              subtitle: "Captura/OCR — pedido na primeira captura", granted: state.screenRecording) {
                    openPrivacyPane("Privacy_ScreenCapture")
                }
                PermissionRow(icon: "internaldrive", tint: .gray, title: "Notificações (Acesso Total ao Disco)",
                              subtitle: "Espelhar notificações do sistema na ilha", granted: state.notifications) {
                    openPrivacyPane("Privacy_AllFiles")
                }
            }
            Spacer()
        }
        .padding(24)
        .task { await state.refresh(notificationsAvailable: coordinator.notifications.available) }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct PermissionRow: View {
    let icon: String, tint: Color, title: String, subtitle: String, granted: Bool
    let ask: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Pedir…", action: ask)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
