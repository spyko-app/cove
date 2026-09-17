import AppKit
import Foundation
import ScriptingBridge

enum RepeatMode: Equatable {
    case off, all, one
}

struct PlayerState: Equatable {
    var shuffle = false
    var repeatMode: RepeatMode = .off
    var favorite: Bool?
    var supportsFavorite = false

    enum Control: Equatable {
        case shuffle(Bool)
        case repeatMode(RepeatMode)
        case favorite(Bool?)
    }

    static func symbol(for control: Control) -> (name: String, tinted: Bool) {
        switch control {
        case .shuffle(let on):
            return ("shuffle", on)
        case .repeatMode(let mode):
            switch mode {
            case .off: return ("repeat", false)
            case .all: return ("repeat", true)
            case .one: return ("repeat.1", true)
            }
        case .favorite(let on):
            return (on == true ? "heart.fill" : "heart", on == true)
        }
    }
}

enum Player: Equatable, CaseIterable {
    case music, spotify

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }
}

@MainActor
final class PlayerBridge: ObservableObject {
    @Published private(set) var state = PlayerState()
    @Published private(set) var isAvailable = false

    var nowPlayingTitleProvider: (() -> String?)?

    private var timer: Timer?
    private var detected: Player?
    private var terminationObservers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        let bundleIDs = Set(Player.allCases.map(\.bundleID))
        terminationObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier,
                  bundleIDs.contains(id) else { return }
            Task { @MainActor in self?.handleAppLifecycleChange() }
        })
        terminationObservers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier,
                  bundleIDs.contains(id) else { return }
            Task { @MainActor in self?.handleAppLifecycleChange() }
        })
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in terminationObservers { center.removeObserver(observer) }
    }

    private func handleAppLifecycleChange() {
        guard timer != nil else { refresh(); return }
        if runningPlayers().isEmpty {
            stopPolling()
            detected = nil
            isAvailable = false
            state = PlayerState()
        } else {
            refresh(nowPlayingTitle: nowPlayingTitleProvider?())
        }
    }

    func startPolling() {
        guard timer == nil else { return }
        refresh(nowPlayingTitle: nowPlayingTitleProvider?())
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(nowPlayingTitle: self?.nowPlayingTitleProvider?()) }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func runningPlayers() -> [Player] {
        Player.allCases.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
    }

    private func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    private func app(for player: Player) -> SBApplication? {
        guard isRunning(player) else { return nil }
        return SBApplication(bundleIdentifier: player.bundleID)
    }

    private func currentTrack(_ app: SBApplication) -> SBObject? {
        app.value(forKey: "currentTrack") as? SBObject
    }

    private func trackName(for player: Player) -> String? {
        guard let app = app(for: player), let track = currentTrack(app) else { return nil }
        return track.value(forKey: "name") as? String
    }

    private func isPlaying(_ player: Player) -> Bool {
        guard let app = app(for: player), let raw = app.value(forKey: "playerState") as? NSNumber else { return false }
        let playing: UInt32 = 0x6B50_5350
        return raw.uint32Value == playing
    }

    nonisolated static func choosePlayer(
        running: [Player],
        nowPlayingTitle: String?,
        titles: [Player: String?],
        playing: [Player: Bool]
    ) -> Player? {
        guard !running.isEmpty else { return nil }
        guard running.count > 1 else { return running.first }
        if let title = nowPlayingTitle, !title.isEmpty {
            if let match = running.first(where: { (titles[$0] ?? nil) == title }) { return match }
        }
        if let match = running.first(where: { playing[$0] == true }) { return match }
        return running.contains(.music) ? .music : running.first
    }

    private func detectPlayer(preferredTitle: String?) -> Player? {
        let running = runningPlayers()
        guard running.count > 1 else { return running.first }
        var titles: [Player: String?] = [:]
        var playing: [Player: Bool] = [:]
        for player in running {
            titles[player] = trackName(for: player)
            playing[player] = isPlaying(player)
        }
        return Self.choosePlayer(running: running, nowPlayingTitle: preferredTitle, titles: titles, playing: playing)
    }

    func refresh(nowPlayingTitle: String? = nil) {
        guard let player = detectPlayer(preferredTitle: nowPlayingTitle), let app = app(for: player) else {
            isAvailable = false
            detected = nil
            state = PlayerState()
            return
        }
        detected = player
        isAvailable = true
        switch player {
        case .music:
            let shuffle = (app.value(forKey: "shuffleEnabled") as? Bool) ?? false
            let repeatMode = Self.musicRepeatMode(from: app.value(forKey: "songRepeat"))
            var favorite: Bool?
            if let track = currentTrack(app) {
                if let f = track.value(forKey: "favorited") as? Bool { favorite = f }
                else if let l = track.value(forKey: "loved") as? Bool { favorite = l }
            }
            state = PlayerState(shuffle: shuffle, repeatMode: repeatMode, favorite: favorite, supportsFavorite: favorite != nil)
        case .spotify:
            let shuffle = (app.value(forKey: "shuffling") as? Bool) ?? false
            let repeating = (app.value(forKey: "repeating") as? Bool) ?? false
            state = PlayerState(shuffle: shuffle, repeatMode: repeating ? .all : .off, favorite: nil, supportsFavorite: false)
        }
    }

    func toggleShuffle() {
        guard let player = detected, let app = app(for: player) else { return }
        switch player {
        case .music: app.setValue(!state.shuffle, forKey: "shuffleEnabled")
        case .spotify: app.setValue(!state.shuffle, forKey: "shuffling")
        }
        refresh(nowPlayingTitle: nowPlayingTitleProvider?())
    }

    func cycleRepeat() {
        guard let player = detected, let app = app(for: player) else { return }
        switch player {
        case .music:
            let next: RepeatMode
            switch state.repeatMode {
            case .off: next = .all
            case .all: next = .one
            case .one: next = .off
            }
            app.setValue(Self.musicRepeatRaw(for: next), forKey: "songRepeat")
        case .spotify:
            app.setValue(!(state.repeatMode == .all), forKey: "repeating")
        }
        refresh(nowPlayingTitle: nowPlayingTitleProvider?())
    }

    func toggleFavorite() {
        guard state.supportsFavorite, let player = detected, player == .music,
              let app = app(for: player), let track = currentTrack(app) else { return }
        let newValue = !(state.favorite ?? false)
        if track.value(forKey: "favorited") != nil {
            track.setValue(newValue, forKey: "favorited")
        } else {
            track.setValue(newValue, forKey: "loved")
        }
        refresh(nowPlayingTitle: nowPlayingTitleProvider?())
    }

    private static let musicRptOff: UInt32 = 0x6B52_704F
    private static let musicRptOne: UInt32 = 0x6B52_7031
    private static let musicRptAll: UInt32 = 0x6B41_6C6C

    private static func musicRepeatMode(from raw: Any?) -> RepeatMode {
        let code: UInt32?
        if let n = raw as? NSNumber { code = n.uint32Value } else { code = nil }
        switch code {
        case musicRptOne: return .one
        case musicRptAll: return .all
        default: return .off
        }
    }

    private static func musicRepeatRaw(for mode: RepeatMode) -> UInt32 {
        switch mode {
        case .off: return musicRptOff
        case .all: return musicRptAll
        case .one: return musicRptOne
        }
    }
}
