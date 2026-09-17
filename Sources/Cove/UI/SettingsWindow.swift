import AppKit
import EventKit
import ServiceManagement
import SwiftUI

/// Janela de Ajustes estilo Alcove: sidebar com seções + panes de toggles.
@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?

    func show(coordinator: NotchCoordinator) {
        if let window {
            window.makeKeyAndOrderFront(nil); window.orderFrontRegardless()
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsRoot(coordinator: coordinator)))
        w.title = "Ajustes do Cove"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.setContentSize(NSSize(width: 720, height: 560))
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window = w
    }
}

private enum Pane: String, CaseIterable, Identifiable {
    case geral = "Geral"
    case aparencia = "Aparência"
    case telas = "Telas"
    case hudsEventos = "HUDs e eventos"
    case ilhaExpandida = "Ilha expandida"
    case droplets = "Droplets"
    case acoesRapidas = "Ações rápidas"
    case cesta = "Cesta"
    case clipboard = "Clipboard"
    case permissoes = "Permissões"
    case atualizacoes = "Atualizações"
    case sobre = "Sobre"

    var id: String { rawValue }

    var icon: (String, Color) {
        switch self {
        case .geral: ("gearshape.fill", .gray)
        case .aparencia: ("paintbrush.fill", .pink)
        case .telas: ("display", .cyan)
        case .hudsEventos: ("bolt.badge.clock.fill", .orange)
        case .ilhaExpandida: ("play.fill", .red)
        case .droplets: ("square.stack.3d.up.fill", .indigo)
        case .acoesRapidas: ("circle.grid.3x3.fill", .blue)
        case .cesta: ("tray.full.fill", .brown)
        case .clipboard: ("doc.on.clipboard", .purple)
        case .permissoes: ("checkmark.shield.fill", .green)
        case .atualizacoes: ("arrow.triangle.2.circlepath", .mint)
        case .sobre: ("info.circle.fill", .gray)
        }
    }

    static let sections: [(String?, [Pane])] = [
        (nil, [.geral, .aparencia, .telas]),
        ("HUDs", [.hudsEventos]),
        ("Ilha", [.ilhaExpandida, .droplets, .acoesRapidas, .cesta, .clipboard]),
        ("Cove", [.permissoes, .atualizacoes, .sobre]),
    ]
}

struct SettingsRoot: View {
    @ObservedObject var coordinator: NotchCoordinator
    @State private var pane: Pane = .geral
    @State private var query = ""

    private var visiblePanes: Set<String> {
        Set(SettingsSearchIndex.coveNotch.matches(query))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                ForEach(Array(Pane.sections.enumerated()), id: \.offset) { _, section in
                    let (title, panes) = section
                    let shown = panes.filter { visiblePanes.contains($0.rawValue) }
                    if !shown.isEmpty {
                        Section(title ?? "") {
                            ForEach(shown) { p in
                                Label {
                                    Text(p.rawValue)
                                } icon: {
                                    Image(systemName: p.icon.0)
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(p.icon.1.gradient,
                                                    in: RoundedRectangle(cornerRadius: 6))
                                }
                                .tag(p)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Buscar ajustes")
            .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 300)
            .onChange(of: query) { _, newValue in
                guard !newValue.isEmpty, !visiblePanes.contains(pane.rawValue) else { return }
                if let first = Pane.sections.flatMap(\.1).first(where: { visiblePanes.contains($0.rawValue) }) {
                    pane = first
                }
            }
        } detail: {
            ScrollView {
                paneView
                    .padding(20)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            .navigationTitle(pane.rawValue)
        }
    }

    @ViewBuilder private var paneView: some View {
        switch pane {
        case .geral: GeneralPane(c: coordinator)
        case .aparencia: AparenciaPane(c: coordinator)
        case .telas: TelasPane(c: coordinator)
        case .hudsEventos: HUDsEventosPane(c: coordinator)
        case .ilhaExpandida: IlhaExpandidaPane(c: coordinator)
        case .droplets: DropletsPane(c: coordinator)
        case .acoesRapidas: AcoesRapidasPane(c: coordinator)
        case .cesta: CestaPane(c: coordinator)
        case .clipboard: ClipboardPolicyPane(c: coordinator)
        case .permissoes: PermissoesPane(c: coordinator)
        case .atualizacoes: AtualizacoesPane()
        case .sobre:
            VStack(alignment: .leading, spacing: 8) {
                Text("Cove").font(.title2.bold())
                Text("Dynamic Island pro Mac — 100% Cove, 100% Swift.")
                Text("Versão \(AppVersion.marketing)").foregroundStyle(.secondary)
            }
        }
    }
}

/// Picker "Estilo deste HUD" (por tipo) — Padrão herda o global, ou override
/// gravado em `hudStyles[kind]`.
private struct HUDStyleRow: View {
    @ObservedObject var c: NotchCoordinator
    let kind: String
    var label: String

    private static let defaultTag = "__default__"

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Picker("", selection: .init(
                get: { c.config.hudStyles[kind] ?? Self.defaultTag },
                set: { v in
                    c.updateConfig {
                        if v == Self.defaultTag { $0.hudStyles.removeValue(forKey: kind) }
                        else { $0.hudStyles[kind] = v }
                    }
                })) {
                Text("Padrão").tag(Self.defaultTag)
                Text("Branco").tag("white")
                Text("Cor de destaque").tag("accent")
                Text("Glow").tag("glow")
            }.frame(width: 170)
        }
    }
}

// MARK: - Geral

private struct GeneralPane: View {
    @ObservedObject var c: NotchCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Login").font(.headline)
            SettingsGroup {
                SettingToggle(title: "Abrir no login", isOn: .init(
                    get: { c.config.launchAtLogin },
                    set: { v in
                        c.updateConfig { $0.launchAtLogin = v }
                        try? (v ? SMAppService.mainApp.register()
                              : SMAppService.mainApp.unregister())
                    }))
            }

            Text("Capturas").font(.headline)
            SettingsGroup {
                SettingToggle(title: "Esconder de capturas de tela", isOn: .init(
                    get: { c.config.hideFromCapture },
                    set: { v in c.updateConfig { $0.hideFromCapture = v }
                           NotchPanelController.current?.applySharing() }))
                SettingToggle(title: "Abrir editor após capturar", isOn: binding(\.openEditorAfterCapture))
            }

            Text("Comportamento").font(.headline)
            SettingsGroup {
                SettingToggle(title: "Feedback háptico", isOn: binding(\.hapticFeedback))
                SettingToggle(title: "Expandir ao passar o mouse", isOn: binding(\.expandOnHover))
                SettingToggle(title: "Gestos verticais (puxar abre / empurrar fecha)", isOn: binding(\.verticalGestures))
                SettingToggle(title: "Esconder em apps de tela cheia", isOn: binding(\.hideInFullscreen))
                SettingSlider(title: "Atraso do hover",
                              value: .init(get: { c.config.hoverDuration },
                                           set: { v in c.updateConfig { $0.hoverDuration = v } }),
                              range: 0...1, step: 0.1, suffix: "s")
            }

            Text("Onboarding").font(.headline)
            SettingsGroup {
                Button("Refazer onboarding…") {
                    c.updateConfig { $0.onboardingDone = false }
                    OnboardingWindowManager.shared.show(coordinator: c)
                }
            }
        }
    }

    private func binding(_ key: WritableKeyPath<NotchConfig, Bool>) -> Binding<Bool> {
        Binding(get: { c.config[keyPath: key] },
                set: { v in c.updateConfig { $0[keyPath: key] = v } })
    }
}

// MARK: - Aparência

/// Todos os `kindKey` de `NotchActivity` (`ActivityQueue.swift`) com rótulo pt-BR
/// — uma tabela única de overrides por tipo de HUD, sem duplicar o picker global.
private let hudKindLabels: [(kind: String, label: String)] = [
    ("volume", "Volume"),
    ("brightness", "Brilho"),
    ("keyboardBrightness", "Teclado"),
    ("battery", "Bateria"),
    ("lowPowerMode", "Baixo consumo"),
    ("device", "Dispositivo"),
    ("wifi", "Wi-Fi"),
    ("hotspot", "Hotspot"),
    ("drive", "Disco"),
    ("vpn", "VPN"),
    ("vpnSession", "Sessão VPN"),
    ("focus", "Foco"),
    ("lock", "Bloqueio"),
    ("event", "Evento"),
    ("eventCountdown", "Contagem regressiva"),
    ("notification", "Notificação"),
    ("track", "Faixa"),
    ("timer", "Timer"),
    ("recording", "Gravação"),
    ("screenRecording", "Gravação de tela"),
    ("highAlert", "High Alert"),
]

private struct AparenciaPane: View {
    @ObservedObject var c: NotchCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Estilo").font(.headline)
            SettingsGroup {
                HStack {
                    Text("Estilo dos HUDs (global)")
                    Spacer()
                    Picker("", selection: .init(
                        get: { c.config.hudStyle },
                        set: { v in c.updateConfig { $0.hudStyle = v } })) {
                        Text("Branco").tag("white")
                        Text("Cor de destaque").tag("accent")
                        Text("Glow").tag("glow")
                    }.frame(width: 170)
                }
                if #available(macOS 26, *) {
                    SettingToggle(title: "Dynamic Glass (macOS 26+)", isOn: .init(
                        get: { c.config.dynamicGlass },
                        set: { v in c.updateConfig { $0.dynamicGlass = v } }))
                    Text("Efeito de vidro líquido nos cards internos da ilha expandida.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("Intensidade do vidro")
                        Spacer()
                        Text("Ultraclaro").font(.caption).foregroundStyle(.secondary)
                        Slider(value: .init(
                            get: { c.config.dynamicGlassTint },
                            set: { v in c.updateConfig { $0.dynamicGlassTint = v } }),
                               in: 0...1)
                            .frame(width: 140)
                        Text("Tingido").font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(!c.config.dynamicGlass)
                }
            }

            Text("Duração").font(.headline)
            SettingsGroup {
                SettingSlider(title: "Peek (volume/brilho)",
                              value: .init(get: { c.config.hudDuration },
                                           set: { v in c.updateConfig { $0.hudDuration = v } }),
                              range: 0.8...5, step: 0.1, suffix: "s")
                SettingSlider(title: "Eventos (bateria/bluetooth/foco)",
                              value: .init(get: { c.config.eventDuration },
                                           set: { v in c.updateConfig { $0.eventDuration = v } }),
                              range: 2...10, step: 0.5, suffix: "s")
            }

            Text("Estilo por tipo de HUD").font(.headline)
            Text("Sobrescreve o estilo global só pra esse tipo. \"Padrão\" segue o global acima.")
                .font(.caption).foregroundStyle(.secondary)
            SettingsGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(hudKindLabels, id: \.kind) { entry in
                        HUDStyleRow(c: c, kind: entry.kind, label: entry.label)
                    }
                }
            }
        }
    }
}

// MARK: - Telas

private struct TelasPane: View {
    @ObservedObject var c: NotchCoordinator
    @State private var screens: [NSScreen] = NSScreen.screens

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup {
                SettingToggle(title: "Notch simulado em telas externas", isOn: .init(
                    get: { c.config.simulatedNotchOnExternal },
                    set: { v in c.updateConfig { $0.simulatedNotchOnExternal = v }
                           NotchPanelController.current?.reload() }))
                HStack {
                    Text("Mostrar em")
                    Spacer()
                    Picker("", selection: .init(
                        get: { c.config.displayOn },
                        set: { v in c.updateConfig { $0.displayOn = v }
                               NotchPanelController.current?.reload() })) {
                        Text("Todas as telas").tag("all")
                        Text("Só a interna").tag("builtin")
                        Text("Só externas").tag("external")
                    }
                    .frame(width: 160)
                }
                HStack {
                    Text("Ilha larga")
                    Spacer()
                    Picker("", selection: .init(
                        get: { c.config.wideIsland },
                        set: { v in c.updateConfig { $0.wideIsland = v } })) {
                        ForEach(WideIslandMode.allCases, id: \.self) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .frame(width: 160)
                }
                ForEach(screens, id: \.coveDisplayID) { screen in
                    let uuid = DisplayIdentity.current(for: screen.coveDisplayID).uuid
                    let builtin = screen.safeAreaInsets.top > 0
                    HStack {
                        Text(screen.localizedName + (builtin ? " (interna)" : ""))
                        Spacer()
                        Picker("", selection: .init(
                            get: { c.config.displayOverrides[uuid].map { $0 ? "show" : "hide" } ?? "default" },
                            set: { v in
                                c.updateConfig {
                                    switch v {
                                    case "show": $0.displayOverrides[uuid] = true
                                    case "hide": $0.displayOverrides[uuid] = false
                                    default: $0.displayOverrides.removeValue(forKey: uuid)
                                    }
                                }
                                NotchPanelController.current?.reload()
                            })) {
                            Text("Padrão").tag("default")
                            Text("Mostrar").tag("show")
                            Text("Ocultar").tag("hide")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                }
                if !DisplayPolicy.anyVisible(
                    screens: screens.map { (DisplayIdentity.current(for: $0.coveDisplayID).uuid, $0.safeAreaInsets.top > 0) },
                    global: c.config.displayOn, overrides: c.config.displayOverrides) {
                    Label("Nenhuma tela mostra a ilha com essa combinação", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }

            Text("Tela de bloqueio").font(.headline)
            SettingsGroup {
                SettingToggle(title: "Mostrar a ilha na tela de bloqueio", isOn: .init(
                    get: { c.config.showOnLockScreen },
                    set: { v in c.updateConfig { $0.showOnLockScreen = v } }))
                    .disabled(!LockScreenBridge.isAvailable)
                Text("Só exibição enquanto bloqueada: HUDs de volume/brilho, mídia tocando, bateria e eventos. Sem hover nem expandir — o input é do macOS.")
                    .font(.caption).foregroundStyle(.secondary)
                if !LockScreenBridge.isAvailable {
                    Label("Indisponível nesta versão do macOS (a ponte SkyLight não carregou)", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }

            Text("Widgets na tela de bloqueio").font(.headline)
            SettingsGroup {
                ForEach(LockScreenWidget.allCases, id: \.self) { w in
                    SettingToggle(title: w.label, isOn: .init(
                        get: { c.config.lockScreenWidgets.contains(w) },
                        set: { on in c.updateConfig { cfg in
                            if on { if !cfg.lockScreenWidgets.contains(w) { cfg.lockScreenWidgets.append(w) } }
                            else { cfg.lockScreenWidgets.removeAll { $0 == w } }
                        } }))
                }
                .disabled(!LockScreenBridge.isAvailable || !c.config.showOnLockScreen)
                Text("Linha de ícone + texto embaixo do relógio, na cor que o macOS dá ao relógio. Só o que tem dado aparece; evento sai como \"Evento 15:00\" (sem título), mídia só tocando.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }
}

// MARK: - HUDs e eventos

private struct HUDsEventosPane: View {
    @ObservedObject var c: NotchCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bateria").font(.headline)
            TogglePane(c: c, rows: [
                ("Eventos de bateria", \.showBatteryEvents),
                ("Avisar economia de energia", \.notifyOnLowPowerMode),
            ]) {
                SettingSlider(title: "Limiar de bateria baixa",
                              value: .init(
                                get: { Double(c.config.lowBatteryThreshold) },
                                set: { v in c.updateConfig { $0.lowBatteryThreshold = Int(v) } }),
                              range: 5...50, step: 5, suffix: "%")
            }

            Text("Conectividade").font(.headline)
            SettingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    SettingToggle(title: "Eventos de Bluetooth/AirPods", isOn: binding(\.showBluetoothEvents))
                    SettingToggle(title: "HUD de Wi-Fi/Hotspot", isOn: binding(\.showWifiHUD))
                    SettingToggle(title: "HUD de drives externos", isOn: binding(\.showDriveHUD))
                    SettingToggle(title: "HUD de VPN com timer de sessão", isOn: binding(\.showVPNHUD))
                    Text("Bateria do dispositivo aparece no peek ao conectar (IORegistry). SSID do Wi-Fi pode não aparecer sem permissão de Localização.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !c.wifiMonitoringAvailable {
                        Text("Monitoramento de Wi-Fi indisponível")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            Text("Foco").font(.headline)
            TogglePane(c: c, rows: [("Eventos de Foco (DND)", \.showFocusEvents)]) { EmptyView() }

            Text("Brilho").font(.headline)
            TogglePane(c: c, rows: [
                ("HUD de brilho na ilha", \.showBrightnessHUD),
                ("HUD do backlight do teclado (F5/F6)", \.keyboardBrightnessHUD),
            ]) { EmptyView() }

            Text("Som").font(.headline)
            TogglePane(c: c, rows: [
                ("HUD de volume na ilha", \.showVolumeHUD),
                ("Sons de eventos", \.eventSounds),
                ("Chime de hora em hora", \.hourlyChime),
            ], requires: ["Chime de hora em hora": \.eventSounds],
               requiresHelp: ["Chime de hora em hora": "Requer Sons de eventos"]) { EmptyView() }

            Text("Bloqueio").font(.headline)
            TogglePane(c: c, rows: [("Eventos de bloqueio/desbloqueio", \.showLockEvents)]) { EmptyView() }

            Text("Notificações").font(.headline)
            SettingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    SettingToggle(title: "Espelhar notificações do sistema na ilha", isOn: binding(\.showNotifications))
                    HStack(spacing: 6) {
                        Image(systemName: c.notifications.available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(c.notifications.available ? .green : .red)
                        Text("Acesso Total ao Disco: \(c.notifications.available ? "concedido" : "negado")")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if !c.notifications.available {
                            Button("Abrir Privacidade…") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .onAppear { c.notifications.recheck() }

            Text("Live Activities").font(.headline)
            SettingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    SettingToggle(title: "Expandir atividade com toque longo", isOn: binding(\.expandActivityOnLongPress))
                    SettingToggle(title: "Expandir sozinha em alertas", isOn: binding(\.expandActivityOnAlert))
                    Text("Segure 0,45 s na ilha fechada pra abrir a atividade em 4 regiões com ações rápidas. Alertas: bateria ≤ 10% sem tomada, evento em 1 min, VPN caiu, gravação parada por erro.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Text("Sistema").font(.headline)
            SettingsGroup {
                SettingToggle(title: "Substituir HUD nativo (teclas de mídia)", isOn: binding(\.suppressSystemHUD))
                Text("Exige Acessibilidade. Se o HUD nativo sumir após crash: pkill -CONT -x OSDUIHelper")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func binding<T>(_ key: WritableKeyPath<NotchConfig, T>) -> Binding<T> {
        Binding(get: { c.config[keyPath: key] },
                set: { v in c.updateConfig { $0[keyPath: key] = v } })
    }
}

// MARK: - Ilha expandida

private struct IlhaExpandidaPane: View {
    @ObservedObject var c: NotchCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Now Playing").font(.headline)
            TogglePane(c: c, rows: [
                ("Waveform ao vivo (captura de áudio)", \.liveWaveform),
                ("Arte em movimento (reage ao áudio)", \.motionArt),
                ("Peek na troca de faixa", \.trackChangePeek),
                ("Letras (LRCLIB, opcional)", \.lyricsEnabled),
            ], requires: ["Arte em movimento (reage ao áudio)": \.liveWaveform],
               requiresHelp: ["Arte em movimento (reage ao áudio)": "Requer Waveform ao vivo"]) {
                LyricsSettingsExtra()
            }

            Text("Calendário").font(.headline)
            TogglePane(c: c, rows: [
                ("Próximos eventos e time-to-leave", \.showCalendar),
                ("Clima na ilha", \.showWeather),
            ]) {
                CalendarSettingsExtra(c: c)
            }

            Text("Busca").font(.headline)
            SettingsGroup {
                SettingToggle(title: "Puxar a ilha pra baixo abre \"Buscar ou perguntar\"", isOn: .init(
                    get: { c.config.pullDownOpensSearch },
                    set: { v in c.updateConfig { $0.pullDownOpensSearch = v } }))
                Text("Arraste a ilha fechada pra baixo (dois dedos) e a Busca abre com o campo focado. Desligado, o gesto só expande a ilha. Requer gestos verticais ligados.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text("Apps fixados").font(.headline)
            PinnedAppsExtra(c: c)
        }
    }
}

/// Apps fixados: aparecem como ícones no expandido (com ou sem mídia).
private struct PinnedAppsExtra: View {
    @ObservedObject var c: NotchCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ícones que ficam na ilha expandida. Clique abre o app. Sem mídia tocando, a ilha abre só com eles.")
                .font(.caption).foregroundStyle(.secondary)
            SettingsGroup {
                ForEach(c.config.pinnedApps, id: \.self) { id in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 22, height: 22)
                            Text(url.deletingPathExtension().lastPathComponent)
                        } else {
                            Text(id).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            c.updateConfig { $0.pinnedApps.removeAll { $0 == id } }
                        } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.red)
                    }
                    .padding(.vertical, 3)
                }
                if c.config.pinnedApps.isEmpty {
                    Text("Nenhum app ainda.").foregroundStyle(.secondary).padding(.vertical, 3)
                }
            }
            Button("Adicionar app…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.application]
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                panel.allowsMultipleSelection = true
                guard panel.runModal() == .OK else { return }
                let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
                c.updateConfig { cfg in
                    for id in ids where !cfg.pinnedApps.contains(id) { cfg.pinnedApps.append(id) }
                }
            }
        }
    }
}

// MARK: - Droplets

/// Droplets (páginas do expandido sem mídia): liga/desliga, reordena, atalhos.
private struct DropletsPane: View {
    @ObservedObject var c: NotchCoordinator
    @State private var dropletHotkeyText: [String: String] = [:]
    @State private var dropletHotkeyInvalid: Set<String> = []
    @FocusState private var dropletHotkeyFocused: Droplet?

    private func commitDropletHotkey(_ droplet: Droplet) {
        let text = dropletHotkeyText[droplet.rawValue] ?? ""
        if text.isEmpty {
            dropletHotkeyInvalid.remove(droplet.rawValue)
            c.updateConfig { $0.dropletHotKeys.removeValue(forKey: droplet.rawValue) }
            return
        }
        guard HotKeyCombo.parse(text) != nil else {
            dropletHotkeyInvalid.insert(droplet.rawValue)
            return
        }
        dropletHotkeyInvalid.remove(droplet.rawValue)
        c.updateConfig { $0.dropletHotKeys[droplet.rawValue] = text }
    }

    private var order: [Droplet] {
        let enabled = c.config.enabledDroplets.compactMap(Droplet.init(rawValue:))
        let rest = Droplet.allCases.filter { $0 != .media && !enabled.contains($0) }
        return enabled + rest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Páginas do expandido quando não há mídia tocando. Arraste pra reordenar.")
                .font(.caption).foregroundStyle(.secondary)

            List {
                ForEach(order, id: \.self) { droplet in
                    HStack {
                        Image(systemName: droplet.symbol).frame(width: 20)
                        Text(droplet.title)
                        Spacer()
                        TextField("atalho", text: Binding(
                            get: { dropletHotkeyText[droplet.rawValue] ?? "" },
                            set: { dropletHotkeyText[droplet.rawValue] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .foregroundStyle(c.failedHotKeys.contains(droplet.rawValue) ? .red : .primary)
                            .focused($dropletHotkeyFocused, equals: droplet)
                            .onAppear { dropletHotkeyText[droplet.rawValue] = c.config.dropletHotKeys[droplet.rawValue] ?? "" }
                            .onSubmit { commitDropletHotkey(droplet) }
                            .onChange(of: dropletHotkeyFocused) { wasFocused, isFocused in
                                if wasFocused == droplet, isFocused != droplet { commitDropletHotkey(droplet) }
                            }
                            // atalho registrou no boot mas falhou (já em uso por outro app) — #40
                            .help(c.failedHotKeys.contains(droplet.rawValue) ? "Atalho em uso por outro app" : "")
                        if dropletHotkeyInvalid.contains(droplet.rawValue) || c.failedHotKeys.contains(droplet.rawValue) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                                .help(c.failedHotKeys.contains(droplet.rawValue) ? "Atalho em uso por outro app" : "")
                        }
                        Toggle("", isOn: .init(
                            get: { c.config.enabledDroplets.contains(droplet.rawValue) },
                            set: { on in
                                c.updateConfig { cfg in
                                    if on {
                                        if !cfg.enabledDroplets.contains(droplet.rawValue) {
                                            cfg.enabledDroplets.append(droplet.rawValue)
                                        }
                                    } else {
                                        guard cfg.enabledDroplets.count > 1 else { return }
                                        cfg.enabledDroplets.removeAll { $0 == droplet.rawValue }
                                    }
                                }
                            }))
                        .labelsHidden()
                        // espelha TourDropletsPage: nunca deixa desabilitar o último droplet ativo.
                        .disabled(c.config.enabledDroplets == [droplet.rawValue])
                        .help(c.config.enabledDroplets == [droplet.rawValue] ? "Pelo menos um droplet" : "")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .onMove { indices, dest in
                    var current = order
                    current.move(fromOffsets: indices, toOffset: dest)
                    c.updateConfig { cfg in
                        cfg.enabledDroplets = current
                            .filter { cfg.enabledDroplets.contains($0.rawValue) }
                            .map(\.rawValue)
                    }
                }
            }
            .listStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)
        }
        // trocar de aba não passa por onSubmit/perda de foco do TextField —
        // sem isso, editar o atalho e sair direto da aba perde a digitação.
        .onDisappear {
            for droplet in Droplet.allCases {
                let text = dropletHotkeyText[droplet.rawValue] ?? ""
                if text.isEmpty || HotKeyCombo.parse(text) != nil { commitDropletHotkey(droplet) }
            }
        }
    }
}

// MARK: - Ações rápidas

private struct AcoesRapidasPane: View {
    @ObservedObject var c: NotchCoordinator
    @State private var hotkeyText = ""
    @State private var hotkeyInvalid = false
    @FocusState private var hotkeyFocused: Bool

    private func commitHotkey() {
        guard let combo = HotKeyCombo.parse(hotkeyText) else { hotkeyInvalid = true; return }
        hotkeyInvalid = false
        _ = combo
        c.updateConfig { $0.ringHotKey = hotkeyText }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Atalho das Ações rápidas").font(.headline)
            SettingsGroup {
                TextField("ctrl+opt+space", text: $hotkeyText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .foregroundStyle(c.failedHotKeys.contains(NotchCoordinator.ringHotKeyFailureKey) ? .red : .primary)
                    .focused($hotkeyFocused)
                    .onAppear { hotkeyText = c.config.ringHotKey }
                    .onChange(of: hotkeyText) { _, newValue in
                        // valida ao vivo (legenda vermelha) — mas SÓ grava no
                        // config em onSubmit/perda de foco, nunca por tecla.
                        hotkeyInvalid = HotKeyCombo.parse(newValue) == nil
                    }
                    .onSubmit { commitHotkey() }
                    .onChange(of: hotkeyFocused) { wasFocused, isFocused in
                        if wasFocused, !isFocused { commitHotkey() }
                    }
                    // atalho registrou no boot mas falhou (já em uso por outro app) — #40
                    .help(c.failedHotKeys.contains(NotchCoordinator.ringHotKeyFailureKey) ? "Atalho em uso por outro app" : "")
                if hotkeyInvalid {
                    Text("Formato: ctrl+opt+space").font(.caption).foregroundStyle(.red)
                } else if c.failedHotKeys.contains(NotchCoordinator.ringHotKeyFailureKey) {
                    Text("Atalho em uso por outro app").font(.caption).foregroundStyle(.red)
                }
            }

            RingActionsSection(c: c)
        }
        .onDisappear {
            if HotKeyCombo.parse(hotkeyText) != nil { commitHotkey() }
        }
    }
}

/// Ações rápidas (ex-Ring): droplet, app ou Atalho, na ordem em que aparecem na grade dentro da ilha.
private struct RingActionsSection: View {
    @ObservedObject var c: NotchCoordinator
    @State private var shortcutText = ""
    @State private var availableShortcuts: [String]?
    @State private var loadingShortcuts = false

    private var actions: [RingAction] { RingAction.normalize(c.config.ringActions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ações rápidas (2 a 8)").font(.headline)
                Spacer()
                Button("Testar") { c.toggleActions() }
                    .help("Abre a ilha na grade de Ações rápidas")
            }
            List {
                ForEach(actions) { action in
                    HStack {
                        Image(systemName: action.symbol)
                            .frame(width: 20)
                            .foregroundStyle(action.isMissing ? .orange : .primary)
                        Text(action.title)
                        if action.isMissing {
                            Text("não encontrado").font(.caption).foregroundStyle(.orange)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            c.updateConfig { $0.ringActions = actions.filter { $0.id != action.id } }
                        } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.red)
                        .disabled(actions.count <= 2)
                    }
                    .padding(.vertical, 3)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .onMove { indices, dest in
                    var current = actions
                    current.move(fromOffsets: indices, toOffset: dest)
                    c.updateConfig { $0.ringActions = current }
                }
            }
            .listStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)

            Menu("Adicionar…") {
                Menu("Droplet") {
                    ForEach(Droplet.allCases.filter { $0 != .media }, id: \.self) { d in
                        Button(d.title) { add(.droplet(d)) }
                    }
                }
                Button("Capturar") { add(.capture(nil)) }
                Button("OCR") { add(.ocr) }
                Button("Cor") { add(.color) }
                Button("Gravar tela") { add(.screenRecord) }
                Button("Pomodoro") { add(.pomodoro) }
                Button("High Alert") { add(.highAlert) }
                Button("App…") { addApp() }
                Button("Atalho…") { loadShortcutsIfNeeded() }
            }

            Picker("Duração padrão do High Alert", selection: .init(
                get: { HighAlert.Duration(rawValue: c.config.highAlertDuration) ?? .infinite },
                set: { d in c.updateConfig { $0.highAlertDuration = d.rawValue } }
            )) {
                ForEach(HighAlert.Duration.allCases, id: \.self) { d in
                    Text(d.label).tag(d)
                }
            }
            .frame(width: 280)

            if loadingShortcuts {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Carregando Atalhos…").foregroundStyle(.secondary)
                }
            }

            if availableShortcuts != nil {
                HStack {
                    TextField("Nome do Atalho", text: $shortcutText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Button("Adicionar") {
                        let name = shortcutText.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        add(.shortcut(name: name))
                        shortcutText = ""
                        availableShortcuts = nil
                    }
                    .disabled(shortcutText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let list = availableShortcuts, !list.isEmpty,
                   !list.contains(shortcutText), !shortcutText.isEmpty {
                    Text("Não está na lista de Atalhos instalados — confira o nome.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func add(_ action: RingAction) {
        c.updateConfig { cfg in
            guard cfg.ringActions.count < 8 else { return }
            cfg.ringActions.append(action)
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.urls.first,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }
        add(.app(bundleID: bundleID))
    }

    /// Lista o output de `shortcuts list` só na primeira abertura do menu — cache por
    /// sessão da aba. `Process`/`waitUntilExit` rodam fora da main thread (Task.detached):
    /// bloquear a main thread aqui trava a janela de Ajustes inteira até o processo voltar.
    private func loadShortcutsIfNeeded() {
        guard availableShortcuts == nil, !loadingShortcuts else { return }
        loadingShortcuts = true
        Task.detached {
            let names = Self.runShortcutsList()
            await MainActor.run {
                availableShortcuts = names
                loadingShortcuts = false
            }
        }
    }

    private nonisolated static func runShortcutsList() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .split(separator: "\n").map(String.init) ?? []
    }
}

// MARK: - Cesta

/// Cesta: widgets arranjáveis (grade sempre presente) + Quick Actions (2-4 slots) + vault do Obsidian.
private struct CestaPane: View {
    @ObservedObject var c: NotchCoordinator

    private static let widgetTitles: [String: String] = [
        "files": "Grade de arquivos",
        "quickActions": "Quick Actions",
        "recent": "Recentes (tira compacta)",
    ]
    private static let actionTitles: [String: String] = [
        "airdrop": "AirDrop",
        "finder": "Mostrar no Finder",
        "compress": "Compactar (zip)",
        "copyPath": "Copiar caminho",
    ]

    private var widgets: [String] { ShelfLayout.normalize(c.config.shelfWidgets) }
    private var actions: [String] { ShelfLayout.normalizeActions(c.config.shelfQuickActions) }

    private func move(_ id: String, by delta: Int) {
        var current = widgets
        guard let idx = current.firstIndex(of: id) else { return }
        let dest = idx + delta
        guard current.indices.contains(dest) else { return }
        current.swapAt(idx, dest)
        c.updateConfig { $0.shelfWidgets = current }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cesta").font(.headline)
            Text("Widgets exibidos na Cesta e a ordem deles. A grade de arquivos é sempre exibida.")
                .font(.caption).foregroundStyle(.secondary)

            SettingsGroup {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(widgets.enumerated()), id: \.element) { index, id in
                        HStack {
                            Text(Self.widgetTitles[id] ?? id)
                            Spacer()
                            Button { move(id, by: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.plain).disabled(index == 0)
                            Button { move(id, by: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.plain).disabled(index == widgets.count - 1)
                            if id != "files" {
                                Toggle("", isOn: .init(
                                    get: { widgets.contains(id) },
                                    set: { on in
                                        c.updateConfig { cfg in
                                            if on {
                                                if !cfg.shelfWidgets.contains(id) { cfg.shelfWidgets.append(id) }
                                            } else {
                                                cfg.shelfWidgets.removeAll { $0 == id }
                                            }
                                        }
                                    }))
                                .labelsHidden()
                            }
                        }
                    }
                    ForEach(Self.widgetTitles.keys.sorted().filter { !widgets.contains($0) }, id: \.self) { id in
                        HStack {
                            Text(Self.widgetTitles[id] ?? id).foregroundStyle(.secondary)
                            Spacer()
                            Toggle("", isOn: .init(
                                get: { false },
                                set: { on in
                                    guard on else { return }
                                    c.updateConfig { $0.shelfWidgets.append(id) }
                                }))
                            .labelsHidden()
                        }
                    }
                }
            }

            Text("Quick Actions (2 a 4)").font(.subheadline)
            SettingsGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<4, id: \.self) { slot in
                        HStack {
                            Text("Slot \(slot + 1)")
                            Spacer()
                            Picker("", selection: .init(
                                get: { slot < actions.count ? actions[slot] : "" },
                                set: { newValue in
                                    var current = actions
                                    if newValue.isEmpty {
                                        if slot < current.count { current.remove(at: slot) }
                                    } else if slot < current.count {
                                        current[slot] = newValue
                                    } else {
                                        current.append(newValue)
                                    }
                                    c.updateConfig { $0.shelfQuickActions = current }
                                })) {
                                if slot >= 2 { Text("Nenhuma").tag("") }
                                ForEach(ShelfLayout.knownActions, id: \.self) { id in
                                    Text(Self.actionTitles[id] ?? id).tag(id)
                                }
                            }
                            .frame(width: 220)
                            .disabled(slot >= 2 && slot > actions.count)
                        }
                    }
                }
            }

            Text("Vault do Obsidian").font(.headline)
            SettingsGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text(c.config.obsidianVaultPath.isEmpty ? "Nenhum vault escolhido" : c.config.obsidianVaultPath)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    HStack {
                        Button("Escolher vault…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            guard panel.runModal() == .OK, let url = panel.url else { return }
                            c.updateConfig { $0.obsidianVaultPath = url.path }
                            c.notesStoreIfLoaded?.reconfigure(vaultPath: url.path)
                        }
                        Button("Usar pasta local") {
                            c.updateConfig { $0.obsidianVaultPath = "" }
                            c.notesStoreIfLoaded?.reconfigure(vaultPath: "")
                        }
                        .disabled(c.config.obsidianVaultPath.isEmpty)
                    }
                }
            }
        }
    }
}

// MARK: - Permissões

private struct PermissoesPane: View {
    @ObservedObject var c: NotchCoordinator
    @StateObject private var state = PermissionState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Todas são opcionais — sem elas o app funciona igual, só sem a feature correspondente.")
                .font(.caption).foregroundStyle(.secondary)

            SettingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    PermissionsRow(icon: "keyboard", tint: .blue, title: "Acessibilidade",
                                   subtitle: "Substituir o HUD de volume/brilho pela ilha", granted: state.accessibility) {
                        c.startKeyTap(prompt: true)
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1))
                            await state.refresh(notificationsAvailable: c.notifications.available)
                        }
                    }
                    PermissionsRow(icon: "calendar", tint: .red, title: "Calendário",
                                   subtitle: "Próximo evento e aviso de hora de sair", granted: state.calendar) {
                        Task { @MainActor in
                            await c.calendar.requestAccessIfNeeded()
                            await state.refresh(notificationsAvailable: c.notifications.available)
                        }
                    }
                    PermissionsRow(icon: "waveform", tint: .purple, title: "Captura de áudio",
                                   subtitle: "Waveform ao vivo do que está tocando", granted: state.audioCapture) {
                        c.waveform?.start()
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1))
                            state.audioCapture = c.waveform?.running ?? false
                        }
                    }
                    PermissionsRow(icon: "airpods", tint: .teal, title: "Bluetooth",
                                   subtitle: "AirPods e fones: conexão e bateria na ilha", granted: state.bluetooth) {
                        c.startBluetooth()
                        state.bluetooth = true
                    }
                    PermissionsRow(icon: "mic.fill", tint: .orange, title: "Microfone",
                                   subtitle: "Memos de voz — pedido ao gravar", granted: state.microphone) {
                        openPrivacyPane("Privacy_Microphone")
                    }
                    PermissionsRow(icon: "waveform.and.mic", tint: .purple, title: "Reconhecimento de fala",
                                   subtitle: "Memos de voz — pedido ao gravar", granted: state.speech) {
                        openPrivacyPane("Privacy_SpeechRecognition")
                    }
                    PermissionsRow(icon: "rectangle.dashed.badge.record", tint: .red, title: "Gravação de Tela",
                                   subtitle: "Captura/OCR — pedido na primeira captura", granted: state.screenRecording) {
                        openPrivacyPane("Privacy_ScreenCapture")
                    }
                    PermissionsRow(icon: "internaldrive", tint: .gray, title: "Notificações (Acesso Total ao Disco)",
                                   subtitle: "Espelhar notificações do sistema na ilha", granted: state.notifications) {
                        openPrivacyPane("Privacy_AllFiles")
                    }
                }
            }

            Text("Automation").font(.headline)
            Text("Pedida sozinha na 1ª vez que a feature correspondente é usada — Música/Spotify pro Now Playing, Mensagens pra atalhos que enviam SMS/iMessage.")
                .font(.caption).foregroundStyle(.secondary)
            SettingsGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Music / Spotify — pedida no 1º uso", systemImage: "music.note")
                        .font(.caption).foregroundStyle(.secondary)
                    Label("Mensagens — pedida no 1º uso", systemImage: "message")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task { await state.refresh(notificationsAvailable: c.notifications.available) }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct PermissionsRow: View {
    let icon: String, tint: Color, title: String, subtitle: String, granted: Bool
    let ask: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6))
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
    }
}

// MARK: - Atualizações

private struct AtualizacoesPane: View {
    @State private var channel = UpdateChannel.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Canal").font(.headline)
            SettingsGroup {
                HStack {
                    Text("Canal de atualização")
                    Spacer()
                    Picker("", selection: $channel) {
                        Text("Estável").tag("stable")
                        Text("Nightly").tag("nightly")
                    }
                    .frame(width: 160)
                    .onChange(of: channel) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: UpdateChannel.defaultsKey)
                    }
                }
                Text("Nightly recebe builds mais recentes, com mais chance de bug.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsGroup {
                Button("Verificar atualizações…") {
                    Updater.shared?.checkForUpdates()
                }
                Text("Versão \(AppVersion.marketing)").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Extras compartilhados

/// Início da semana + lista de calendários com toggles — carregada de forma
/// assíncrona (Droppy #19: nunca bloquear a aba abrindo o EventKit na hora).
private struct LyricsSettingsExtra: View {
    @State private var cleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Consulta lrclib.net — serviço de terceiros com cobertura parcial. Título/artista/duração são enviados.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(cleared ? "Cache limpo" : "Limpar cache de letras") {
                LyricsService.clearCache()
                cleared = true
            }
        }
    }
}

private struct CalendarSettingsExtra: View {
    @ObservedObject var c: NotchCoordinator
    @State private var calendars: [(id: String, title: String, color: CGColor)]?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Semana começa em")
                Spacer()
                Picker("", selection: .init(
                    get: { c.config.firstWeekday },
                    set: { v in c.updateConfig { $0.firstWeekday = v } })) {
                    Text("Domingo").tag(1)
                    Text("Segunda").tag(2)
                }
                .frame(width: 160)
            }

            Text("Calendários").font(.headline)
            SettingsGroup {
                if let calendars {
                    if calendars.isEmpty {
                        switch EKEventStore.authorizationStatus(for: .event) {
                        case .denied, .restricted:
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Sem permissão de Calendário").foregroundStyle(.secondary)
                                Button("Abrir Privacidade…") {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                                }
                                .controlSize(.small)
                            }
                        case .notDetermined:
                            Button("Pedir acesso…") {
                                Task { @MainActor in
                                    await c.calendar.requestAccessIfNeeded()
                                    await loadCalendars()
                                }
                            }
                            .controlSize(.small)
                        default:
                            Text("Nenhum calendário encontrado.").foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(calendars, id: \.id) { cal in
                            Toggle(isOn: isSelected(cal.id)) {
                                Label {
                                    Text(cal.title)
                                } icon: {
                                    Circle().fill(Color(cgColor: cal.color)).frame(width: 10, height: 10)
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(.vertical, 2)
                        }
                        Text("Nenhum marcado = mostra todos.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Carregando calendários…").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task { await loadCalendars() }
    }

    private func isSelected(_ id: String) -> Binding<Bool> {
        Binding(
            get: { c.config.calendarIDs.contains(id) },
            set: { on in
                c.updateConfig { cfg in
                    if on {
                        if !cfg.calendarIDs.contains(id) { cfg.calendarIDs.append(id) }
                    } else {
                        cfg.calendarIDs.removeAll { $0 == id }
                    }
                }
            })
    }

    private func loadCalendars() async {
        let list = c.calendar.calendars()
        calendars = list
    }
}

/// Retenção, limite e comportamento do histórico do clipboard.
private struct ClipboardPolicyPane: View {
    @ObservedObject var c: NotchCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Retenção").font(.headline)
            SettingsGroup {
                HStack {
                    Text("Manter histórico por")
                    Spacer()
                    Picker("", selection: .init(
                        get: { c.config.clipboardRetentionDays },
                        set: { v in c.updateConfig { $0.clipboardRetentionDays = v } })) {
                        Text("Sem limite").tag(0)
                        Text("1 dia").tag(1)
                        Text("7 dias").tag(7)
                        Text("30 dias").tag(30)
                    }.frame(width: 170)
                }
            }

            Text("Limite").font(.headline)
            SettingsGroup {
                HStack {
                    Text("Máximo de itens")
                    Spacer()
                    Picker("", selection: .init(
                        get: { c.config.clipboardLimit },
                        set: { v in c.updateConfig { $0.clipboardLimit = v } })) {
                        Text("50").tag(50)
                        Text("200").tag(200)
                        Text("1000").tag(1000)
                        Text("Ilimitado").tag(0)
                    }.frame(width: 170)
                }
                Text("Itens fixados nunca são removidos pelo limite ou pela retenção.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text("Ao sair").font(.headline)
            SettingsGroup {
                SettingToggle(title: "Limpar histórico ao sair do Cove", isOn: .init(
                    get: { c.config.clearClipboardOnQuit },
                    set: { v in c.updateConfig { $0.clearClipboardOnQuit = v } }))
            }
        }
    }
}

private struct TogglePane<Extra: View>: View {
    @ObservedObject var c: NotchCoordinator
    let rows: [(String, WritableKeyPath<NotchConfig, Bool>)]
    /// Chave que precisa estar ligada pra essa linha fazer sentido (ex.: "Chime
    /// de hora em hora" exige "Sons de eventos"). Vazio = sempre habilitado.
    var requires: [String: WritableKeyPath<NotchConfig, Bool>] = [:]
    var requiresHelp: [String: String] = [:]
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup {
                ForEach(rows, id: \.0) { title, key in
                    let requirement = requires[title]
                    let enabled = requirement.map { c.config[keyPath: $0] } ?? true
                    SettingToggle(title: title, isOn: .init(
                        get: { c.config[keyPath: key] },
                        set: { v in c.updateConfig { $0[keyPath: key] = v } }))
                        .disabled(!enabled)
                        .help(!enabled ? (requiresHelp[title] ?? "") : "")
                }
            }
            extra()
        }
    }
}

// MARK: - Componentes

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SettingToggle: View {
    let title: String
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .padding(.vertical, 2)
    }
}

private struct SettingSlider: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Slider(value: value, in: range, step: step).frame(width: 140)
            Text("\(value.wrappedValue, specifier: step < 1 ? "%.1f" : "%.0f")\(suffix)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
