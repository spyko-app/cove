import Foundation

struct NotchConfig: Codable {
    var hudDuration: Double = 1.6
    var eventDuration: Double = 3.0
    var lowBatteryThreshold: Int = 20
    var notifyOnLowPowerMode = true
    var showVolumeHUD = true
    var showBrightnessHUD = true
    var showBatteryEvents = true
    var showBluetoothEvents = true
    var showWifiHUD = true
    var showDriveHUD = true
    var showVPNHUD = true
    var simulatedNotchOnExternal = true
    var expandOnHover = true
    var suppressSystemHUD = true
    var showCalendar = true
    var showWeather = true
    var showFocusEvents = true
    var showLockEvents = true
    var hourlyChime = false
    var eventSounds = true
    var liveWaveform = true
    var motionArt = false
    var showNotifications = true
    var launchAtLogin = false
    var hideFromCapture = false
    var displayOn = "all"
    var displayOverrides: [String: Bool] = [:]
    var hoverDuration = 0.1
    var hapticFeedback = true
    var trackChangePeek = true
    var hudStyle = "white"
    var hudStyles: [String: String] = [:]
    var hideInFullscreen = true
    var showOnLockScreen = true
    var lockScreenWidgets: [LockScreenWidget] = LockScreenWidget.defaults
    var keyboardBrightnessHUD = true
    var verticalGestures = true
    var pullDownOpensSearch = true
    var onboardingDone = false
    var pinnedApps: [String] = []
    var enabledDroplets: [String] = ["shelf", "clipboard", "tools", "search", "apps"]
    var shelfWidgets: [String] = ["files", "quickActions"]
    var shelfQuickActions: [String] = ["airdrop", "finder", "compress", "copyPath"]
    var ringHotKey = "ctrl+opt+space"
    var dropletHotKeys: [String: String] = [:]
    var ringActions: [RingAction] = RingAction.defaults
    var obsidianVaultPath = ""
    var clipboardRetentionDays = 0
    var clipboardLimit = 200
    var clearClipboardOnQuit = false
    var openEditorAfterCapture = true
    var calendarIDs: [String] = []
    var firstWeekday = Calendar.current.firstWeekday
    var highAlertDuration = 0
    var dynamicGlass = false
    var dynamicGlassTint: Double = 0.55
    var lyricsEnabled = false
    var expandActivityOnLongPress = true
    var expandActivityOnAlert = true
    var wideIsland: WideIslandMode = .externalOnly

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hudDuration = try c.decodeIfPresent(Double.self, forKey: .hudDuration) ?? 1.6
        eventDuration = try c.decodeIfPresent(Double.self, forKey: .eventDuration) ?? 3.0
        lowBatteryThreshold = try c.decodeIfPresent(Int.self, forKey: .lowBatteryThreshold) ?? 20
        notifyOnLowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .notifyOnLowPowerMode) ?? true
        showVolumeHUD = try c.decodeIfPresent(Bool.self, forKey: .showVolumeHUD) ?? true
        showBrightnessHUD = try c.decodeIfPresent(Bool.self, forKey: .showBrightnessHUD) ?? true
        showBatteryEvents = try c.decodeIfPresent(Bool.self, forKey: .showBatteryEvents) ?? true
        showBluetoothEvents = try c.decodeIfPresent(Bool.self, forKey: .showBluetoothEvents) ?? true
        showWifiHUD = try c.decodeIfPresent(Bool.self, forKey: .showWifiHUD) ?? true
        showDriveHUD = try c.decodeIfPresent(Bool.self, forKey: .showDriveHUD) ?? true
        showVPNHUD = try c.decodeIfPresent(Bool.self, forKey: .showVPNHUD) ?? true
        simulatedNotchOnExternal = try c.decodeIfPresent(Bool.self, forKey: .simulatedNotchOnExternal) ?? true
        expandOnHover = try c.decodeIfPresent(Bool.self, forKey: .expandOnHover) ?? true
        suppressSystemHUD = try c.decodeIfPresent(Bool.self, forKey: .suppressSystemHUD) ?? true
        showCalendar = try c.decodeIfPresent(Bool.self, forKey: .showCalendar) ?? true
        showWeather = try c.decodeIfPresent(Bool.self, forKey: .showWeather) ?? true
        showFocusEvents = try c.decodeIfPresent(Bool.self, forKey: .showFocusEvents) ?? true
        showLockEvents = try c.decodeIfPresent(Bool.self, forKey: .showLockEvents) ?? true
        hourlyChime = try c.decodeIfPresent(Bool.self, forKey: .hourlyChime) ?? false
        eventSounds = try c.decodeIfPresent(Bool.self, forKey: .eventSounds) ?? true
        liveWaveform = try c.decodeIfPresent(Bool.self, forKey: .liveWaveform) ?? true
        motionArt = try c.decodeIfPresent(Bool.self, forKey: .motionArt) ?? false
        showNotifications = try c.decodeIfPresent(Bool.self, forKey: .showNotifications) ?? true
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        hideFromCapture = try c.decodeIfPresent(Bool.self, forKey: .hideFromCapture) ?? false
        displayOn = try c.decodeIfPresent(String.self, forKey: .displayOn) ?? "all"
        displayOverrides = try c.decodeIfPresent([String: Bool].self, forKey: .displayOverrides) ?? [:]
        hoverDuration = try c.decodeIfPresent(Double.self, forKey: .hoverDuration) ?? 0.1
        hapticFeedback = try c.decodeIfPresent(Bool.self, forKey: .hapticFeedback) ?? true
        trackChangePeek = try c.decodeIfPresent(Bool.self, forKey: .trackChangePeek) ?? true
        hudStyle = try c.decodeIfPresent(String.self, forKey: .hudStyle) ?? "white"
        hudStyles = try c.decodeIfPresent([String: String].self, forKey: .hudStyles) ?? [:]
        hideInFullscreen = try c.decodeIfPresent(Bool.self, forKey: .hideInFullscreen) ?? true
        showOnLockScreen = try c.decodeIfPresent(Bool.self, forKey: .showOnLockScreen) ?? true
        lockScreenWidgets = LockScreenWidget.decode((try? c.decodeIfPresent([String].self, forKey: .lockScreenWidgets)) ?? nil)
        keyboardBrightnessHUD = try c.decodeIfPresent(Bool.self, forKey: .keyboardBrightnessHUD) ?? true
        verticalGestures = try c.decodeIfPresent(Bool.self, forKey: .verticalGestures) ?? true
        pullDownOpensSearch = try c.decodeIfPresent(Bool.self, forKey: .pullDownOpensSearch) ?? true
        onboardingDone = try c.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? false
        pinnedApps = try c.decodeIfPresent([String].self, forKey: .pinnedApps) ?? []
        enabledDroplets = try c.decodeIfPresent([String].self, forKey: .enabledDroplets) ?? ["shelf", "clipboard", "tools", "search", "apps"]
        shelfWidgets = try c.decodeIfPresent([String].self, forKey: .shelfWidgets) ?? ["files", "quickActions"]
        shelfQuickActions = try c.decodeIfPresent([String].self, forKey: .shelfQuickActions) ?? ["airdrop", "finder", "compress", "copyPath"]
        ringHotKey = try c.decodeIfPresent(String.self, forKey: .ringHotKey) ?? "ctrl+opt+space"
        dropletHotKeys = try c.decodeIfPresent([String: String].self, forKey: .dropletHotKeys) ?? [:]
        if var nested = try? c.nestedUnkeyedContainer(forKey: .ringActions) {
            ringActions = RingAction.normalize((try? RingActionListCoding.decode(&nested)) ?? RingAction.defaults)
        } else {
            ringActions = RingAction.defaults
        }
        obsidianVaultPath = try c.decodeIfPresent(String.self, forKey: .obsidianVaultPath) ?? ""
        clipboardRetentionDays = try c.decodeIfPresent(Int.self, forKey: .clipboardRetentionDays) ?? 0
        clipboardLimit = try c.decodeIfPresent(Int.self, forKey: .clipboardLimit) ?? 200
        clearClipboardOnQuit = try c.decodeIfPresent(Bool.self, forKey: .clearClipboardOnQuit) ?? false
        openEditorAfterCapture = try c.decodeIfPresent(Bool.self, forKey: .openEditorAfterCapture) ?? true
        calendarIDs = try c.decodeIfPresent([String].self, forKey: .calendarIDs) ?? []
        firstWeekday = try c.decodeIfPresent(Int.self, forKey: .firstWeekday) ?? Calendar.current.firstWeekday
        highAlertDuration = try c.decodeIfPresent(Int.self, forKey: .highAlertDuration) ?? 0
        dynamicGlass = try c.decodeIfPresent(Bool.self, forKey: .dynamicGlass) ?? false
        dynamicGlassTint = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .dynamicGlassTint) ?? 0.55))
        lyricsEnabled = try c.decodeIfPresent(Bool.self, forKey: .lyricsEnabled) ?? false
        expandActivityOnLongPress = try c.decodeIfPresent(Bool.self, forKey: .expandActivityOnLongPress) ?? true
        expandActivityOnAlert = try c.decodeIfPresent(Bool.self, forKey: .expandActivityOnAlert) ?? true
        wideIsland = WideIslandMode(rawValue: (try? c.decodeIfPresent(String.self, forKey: .wideIsland)) ?? nil ?? "") ?? .externalOnly
    }
}

enum NotchConfigStore {
    private static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cove/config.json")
    }

    static func load() -> NotchConfig {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(NotchConfig.self, from: data)
        else { return NotchConfig() }
        return cfg
    }

    static func save(_ cfg: NotchConfig) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(cfg).write(to: url)
    }
}

enum AppEnvironment {
    static let isBundledApp = Bundle.main.bundlePath.hasSuffix(".app")
}
