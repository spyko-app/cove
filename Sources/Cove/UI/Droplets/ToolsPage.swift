import AppKit
import SwiftUI

/// Menu de modo de captura — usado pelo cartão de Ferramentas e pela ação
/// "Capturar" da grade de Ações rápidas (aperta e segura abre o menu; toque
/// solto continua sendo região, o padrão).
@MainActor func popCaptureModeMenu(_ coordinator: NotchCoordinator) {
    NotchActions.popMenu([
        ("Região", { coordinator.capture(.region, to: .shelf) }),
        ("Janela", { coordinator.capture(.window, to: .shelf) }),
        ("Tela inteira", { coordinator.capture(.fullScreen, to: .shelf) }),
        ("Timer 5s", { coordinator.capture(.timer(seconds: 5), to: .shelf) }),
        (coordinator.screenRecorder.isRecording ? "Parar gravação" : "Gravar tela",
         { coordinator.screenRecorder.isRecording ? coordinator.stopScreenRecording() : coordinator.startScreenRecording() }),
    ])
}

struct ToolsPage: View {
    @ObservedObject var coordinator: NotchCoordinator
    let notchTop: CGFloat

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: notchTop)
            Group {
                if #available(macOS 26, *) {
                    GlassEffectContainer(spacing: 4) { grid }
                } else {
                    grid
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            PomodoroCard(timers: coordinator.timers)
            TimerCard(timers: coordinator.timers)
            HighAlertCard(highAlert: coordinator.highAlert)
            BatteryCard()
            CaptureCard(coordinator: coordinator)
            RecordCard(coordinator: coordinator)
        }
    }
}

/// Botão que ocupa o cartão inteiro: realce retangular no hover, encolhe ao pressionar.
struct CardButtonStyle: ButtonStyle {
    @State private var over = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(over ? 0.10 : 0)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.16), value: over)
            .animation(.spring(duration: 0.14, bounce: 0.25), value: configuration.isPressed)
            .onHover { o in
                guard o != over else { return }
                over = o
                if o { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            }
    }
}

private struct ToolCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .padding(5)
            .coveCardBackground(cornerRadius: 12)
    }
}

/// Anatomia comum de todo cartão: linha 1 = ícone + título (+ status opcional
/// à direita), linha 2 = controles — empilhados verticalmente pra caber nas
/// colunas estreitas da grade de 3.
private struct ToolCardRow<Icon: View, Trailing: View, Controls: View>: View {
    let title: String
    let icon: Icon
    let trailing: Trailing
    let controls: Controls
    var onTitleTap: (() -> Void)?

    init(
        title: String,
        onTitleTap: (() -> Void)? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder controls: () -> Controls
    ) {
        self.title = title
        self.onTitleTap = onTitleTap
        self.icon = icon()
        self.trailing = trailing()
        self.controls = controls()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                icon
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture { onTitleTap?() }
                Spacer(minLength: 0)
                trailing
            }
            .frame(height: 20)
            HStack(spacing: 4) {
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
    }
}

/// Chip-cápsula compartilhado pelos controles de todo cartão de ferramenta.
/// Hover/press cobrem exatamente o formato da cápsula (não só o glifo).
private struct ToolChip: View {
    var symbol: String? = nil
    var label: String? = nil
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
                if let label { Text(label) }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(active ? .yellow : .white)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
        }
        .buttonStyle(ToolChipButtonStyle(active: active))
    }
}

private struct ToolChipButtonStyle: ButtonStyle {
    var active: Bool
    @State private var over = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule())
            .background(Capsule().fill(.white.opacity(over ? 0.18 : (active ? 0.25 : 0.10))))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.smooth(duration: 0.14), value: over)
            .animation(.spring(duration: 0.14, bounce: 0.25), value: configuration.isPressed)
            .onHover { o in
                guard o != over else { return }
                over = o
            }
    }
}

/// Botão ícone+rótulo empilhado (usado na Captura): hover/press cobrem
/// ícone e rótulo juntos, não só o glifo (diferente do NotchHover circular).
private struct ToolIconButton: View {
    let symbol: String
    let label: String
    var tint: Color = .white.opacity(0.85)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(tint)
                Text(label).font(.system(size: 7)).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .buttonStyle(ToolIconButtonStyle())
    }
}

private struct ToolIconButtonStyle: ButtonStyle {
    @State private var over = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(over ? 0.14 : 0)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.smooth(duration: 0.14), value: over)
            .animation(.spring(duration: 0.14, bounce: 0.25), value: configuration.isPressed)
            .onHover { o in
                guard o != over else { return }
                over = o
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
    }
}

private struct PomodoroCard: View {
    @ObservedObject var timers: TimerService

    private var isPomodoro: Bool {
        guard let s = timers.session else { return false }
        return s.label == "Pomodoro" || s.label == "Pausa"
    }

    var body: some View {
        ToolCard {
            ToolCardRow(title: "Pomodoro") {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                    if isPomodoro, let s = timers.session {
                        Circle()
                            .trim(from: 0, to: CGFloat(s.remaining) / CGFloat(max(s.total, 1)))
                            .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Text(isPomodoro ? mmss(timers.session?.remaining ?? 0) : "25")
                        .font(.system(size: 6.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1).fixedSize()
                }
                .frame(width: 22, height: 22)
            } controls: {
                HStack(spacing: 4) {
                    if isPomodoro, let s = timers.session {
                        ToolChip(symbol: s.isRunning ? "pause.fill" : "play.fill") {
                            s.isRunning ? timers.pause() : timers.resume()
                        }
                        ToolChip(symbol: "stop.fill") { timers.stop() }
                    } else {
                        ToolChip(symbol: "play.fill", label: "Iniciar") {
                            timers.start(label: "Pomodoro", seconds: TimerService.pomodoroWork)
                        }
                    }
                }
            }
        }
    }

    private func mmss(_ s: Int) -> String { String(format: "%02d:%02d", s / 60, s % 60) }
}

private struct TimerCard: View {
    @ObservedObject var timers: TimerService
    @State private var editingCustom = false
    @State private var minutes = ""
    @FocusState private var minutesFocused: Bool

    var body: some View {
        ToolCard {
            ToolCardRow(title: "Timer", onTitleTap: { editingCustom = true; minutesFocused = true }) {
                Image(systemName: "timer")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
            } controls: {
                if editingCustom {
                    TextField("min", text: $minutes)
                        .textFieldStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(width: 34)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.10)))
                        .focused($minutesFocused)
                        .onSubmit {
                            guard let m = Int(minutes), m > 0 else { return }
                            timers.start(label: "Timer", seconds: m * 60)
                            minutes = ""
                            editingCustom = false
                        }
                } else if let s = timers.session, s.label == "Timer" {
                    // timer rodando: tempo + pausar/retomar + parar (antes só dava pra iniciar)
                    HStack(spacing: 4) {
                        Text(String(format: "%02d:%02d", s.remaining / 60, s.remaining % 60))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        ToolChip(symbol: s.isRunning ? "pause.fill" : "play.fill") {
                            s.isRunning ? timers.pause() : timers.resume()
                        }
                        ToolChip(symbol: "stop.fill") { timers.stop() }
                    }
                } else {
                    HStack(spacing: 4) {
                        ForEach([5, 10, 15, 30], id: \.self) { m in
                            ToolChip(label: "\(m)") { timers.start(label: "Timer", seconds: m * 60) }
                        }
                    }
                }
            }
        }
    }
}

private struct HighAlertCard: View {
    @ObservedObject var highAlert: HighAlert

    var body: some View {
        ToolCard {
            ToolCardRow(title: "High Alert") {
                Button(action: { highAlert.toggle() }) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(highAlert.isOn ? .yellow : .white.opacity(0.85))
                }
                .buttonStyle(.plain)
            } trailing: {
                statusLabel
            } controls: {
                HStack(spacing: 4) {
                    ForEach(HighAlert.Duration.allCases, id: \.self) { d in
                        let active = highAlert.isOn && highAlert.lastDuration == d
                        ToolChip(label: d.label, active: active) { highAlert.start(d) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var statusLabel: some View {
        if highAlert.isOn, let expiresAt = highAlert.expiresAt {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let remaining = max(Int(expiresAt.timeIntervalSince(ctx.date).rounded()), 0)
                Text(mmss(remaining))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.yellow)
            }
        } else if highAlert.isOn {
            Text("∞")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.yellow)
        } else {
            EmptyView()
        }
    }

    private func mmss(_ s: Int) -> String { String(format: "%02d:%02d", s / 60, s % 60) }
}

/// Captura, OCR e cor num único card — segurar/clique-direito na Cesta abre o menu de modo.
private struct CaptureCard: View {
    @ObservedObject var coordinator: NotchCoordinator
    @ObservedObject private var screenRecorder: ScreenRecorder

    init(coordinator: NotchCoordinator) {
        self.coordinator = coordinator
        self.screenRecorder = coordinator.screenRecorder
    }

    var body: some View {
        ToolCard {
            ToolCardRow(title: "Captura") {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
            } controls: {
                HStack(spacing: 2) {
                    Button(action: { coordinator.captureToShelf() }) {
                        VStack(spacing: 2) {
                            Image(systemName: "camera.viewfinder").font(.system(size: 13))
                            Text("Cesta").font(.system(size: 7)).lineLimit(1).fixedSize()
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(ToolIconButtonStyle())
                    .onLongPressGesture(minimumDuration: 0.35) { popCaptureModeMenu(coordinator) }
                    .contextMenu {
                        Button("Região") { coordinator.capture(.region, to: .shelf) }
                        Button("Janela") { coordinator.capture(.window, to: .shelf) }
                        Button("Tela inteira") { coordinator.capture(.fullScreen, to: .shelf) }
                        Button("Timer 5s") { coordinator.capture(.timer(seconds: 5), to: .shelf) }
                    }

                    ToolIconButton(symbol: "text.viewfinder", label: "OCR") { coordinator.captureForOCR() }
                    ToolIconButton(symbol: "eyedropper", label: "Cor") { coordinator.pickColor() }
                    ToolIconButton(
                        symbol: screenRecorder.isRecording ? "stop.circle.fill" : "record.circle",
                        label: "Tela",
                        tint: screenRecorder.isRecording ? .red : .white.opacity(0.85),
                        action: toggleScreenRecording)
                }
                .foregroundStyle(.white.opacity(coordinator.isCapturing ? 0.4 : 0.85))
                .disabled(coordinator.isCapturing)
            }
        }
    }

    private func toggleScreenRecording() {
        if screenRecorder.isRecording {
            coordinator.stopScreenRecording()
        } else {
            coordinator.startScreenRecording()
        }
    }
}

private struct RecordCard: View {
    @ObservedObject var coordinator: NotchCoordinator
    @ObservedObject private var voice: VoiceMemoService

    init(coordinator: NotchCoordinator) {
        self.coordinator = coordinator
        self.voice = coordinator.voice
    }

    var body: some View {
        ToolCard {
            ToolCardRow(title: "Gravar") {
                Button(action: toggle) {
                    Image(systemName: voice.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(voice.isRecording ? .red : .white.opacity(0.85))
                }
                .buttonStyle(.plain)
            } controls: {
                if voice.isRecording {
                    HStack(spacing: 4) {
                        Text(mmss(voice.elapsed))
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                        LevelBar(level: voice.level).frame(width: 34)
                    }
                } else if let error = voice.lastError {
                    Text(error).font(.system(size: 8)).foregroundStyle(.red).lineLimit(1)
                } else if !voice.transcript.isEmpty {
                    HStack(spacing: 4) {
                        if AXIsProcessTrusted() {
                            ToolChip(label: "Colar", action: pasteTranscript)
                        }
                        ToolChip(label: "Copiar", action: copyTranscript)
                    }
                } else {
                    ToolChip(label: "Memo de voz", action: toggle)
                }
            }
        }
    }

    private func toggle() {
        if voice.isRecording {
            Task {
                guard let url = await voice.stop() else { return }
                coordinator.shelf.add([url])
                coordinator.notify(app: "Memo", title: String(voice.transcript.prefix(40)))
            }
        } else {
            Task { await voice.start() }
        }
    }

    private func mmss(_ s: Int) -> String { String(format: "%02d:%02d", s / 60, s % 60) }

    /// A ilha está em foco no clique — PasteAtCursor mira no último app não-Cove.
    private func pasteTranscript() {
        let pasted = PasteAtCursor.paste(voice.transcript)
        coordinator.notify(app: "Memo", title: pasted ? "Transcrição colada" : "Não foi possível colar (app alvo ou Acessibilidade)")
    }

    private func copyTranscript() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(voice.transcript, forType: .string)
        coordinator.notify(app: "Memo", title: "Transcrição copiada")
    }
}

private struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.15))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.red)
                        .frame(width: geo.size.width * CGFloat(level))
                }
        }
        .frame(height: 4)
    }
}

private struct BatteryCard: View {
    private func percentText(_ state: PowerService.BatteryState?) -> String {
        state.map { "\($0.percent)%" } ?? "—"
    }

    private func symbolName(_ state: PowerService.BatteryState?) -> String {
        guard let s = state else { return "battery.0percent" }
        if s.charging { return "battery.100percent.bolt" }
        switch s.percent {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func statusText(_ state: PowerService.BatteryState?) -> String {
        guard let s = state else { return "" }
        if s.charging { return "Carregando" }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return "Baixo consumo" }
        return "Bateria"
    }

    // Sem estado publicado pelo coordinator pra bateria — reamostra a cada
    // 30s enquanto o card está visível (item 9 da auditoria).
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let state = PowerService.read()
            ToolCard {
                ToolCardRow(title: percentText(state)) {
                    Image(systemName: symbolName(state))
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                } controls: {
                    Button(action: openBatterySettings) {
                        Text(statusText(state))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings-extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
