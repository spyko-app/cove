import AppKit
import Combine
import SwiftUI

extension NSScreen {
    var coveDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class DropHostView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onDragEnter: (() -> Void)?
    var isInsideIsland: ((NSPoint) -> Bool)?
    var isDragActive: (() -> Bool)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? {
        (isDragActive?() ?? false) ? self : nil
    }
    private func inside(_ sender: NSDraggingInfo) -> Bool { isInsideIsland?(sender.draggingLocation) ?? true }
    private static let debug = ProcessInfo.processInfo.environment["COVE_DEBUG"] != nil
    static func dlog(_ m: String) { if debug { FileHandle.standardError.write("[drop] \(m)\n".data(using: .utf8)!) } }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.dlog("entered loc=\(sender.draggingLocation) inside=\(inside(sender))")
        guard inside(sender) else { return [] }
        onDragEnter?(); return .copy
    }
    private var lastUpdateLog = Date.distantPast
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let ok = inside(sender)
        if Date().timeIntervalSince(lastUpdateLog) > 0.1 {
            lastUpdateLog = Date()
            Self.dlog("updated loc=\(sender.draggingLocation) inside=\(ok)")
        }
        return ok ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { Self.dlog("exited") }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Self.dlog("prepare loc=\(sender.draggingLocation) inside=\(inside(sender))"); return inside(sender)
    }
    override func draggingEnded(_ sender: NSDraggingInfo) { Self.dlog("ended loc=\(sender.draggingLocation)") }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Self.dlog("perform loc=\(sender.draggingLocation) inside=\(inside(sender))")
        guard inside(sender) else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(urls); return true
    }
}

@MainActor
final class NotchPanelController {
    static var current: NotchPanelController?
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    let coordinator: NotchCoordinator

    private var scrollMonitor: Any?
    private var lastDragCount = 0
    private var swipeAccum: CGFloat = 0
    private var swipeAccumY: CGFloat = 0
    private var swipeFired = false
    private var fullscreenTimer: Timer?
    private var hiddenForFullscreen: [CGDirectDisplayID: Bool] = [:]
    private var hiddenBeforeLock: [CGDirectDisplayID: Bool] = [:]
    private var lastSignature: String?
    private var reloadTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var dragPollTask: Task<Void, Never>?
    static let panelSize = NSSize(width: 760, height: 300)
    private var loweredLevelCount = 0
    private(set) var lockScreenActive = false
    private var unlockGraceUntil = Date.distantPast
    private var lockWidgets: LockWidgetsController?

    init(coordinator: NotchCoordinator) {
        self.coordinator = coordinator
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] ev in
            guard let self, let win = ev.window as? NSPanel, panels.values.contains(win) else { return ev }
            if ev.phase == .began || ev.momentumPhase == .ended {
                swipeAccum = 0; swipeAccumY = 0; swipeFired = false
            }
            let expanded = coordinator.isExpanded
            let scrollsInternally = expanded && (coordinator.currentDroplet?.scrollsInternally ?? false)
            if ev.momentumPhase != [] { return scrollsInternally ? ev : nil }
            if ev.phase == .ended || ev.phase == .cancelled {
                swipeAccum = 0; swipeAccumY = 0; swipeFired = false
                return scrollsInternally ? ev : nil
            }
            guard !swipeFired else { return scrollsInternally ? ev : nil }
            swipeAccum += ev.scrollingDeltaX
            swipeAccumY += ev.scrollingDeltaY
            if ProcessInfo.processInfo.environment["COVE_DEBUG"] != nil {
                FileHandle.standardError.write("[swipe] dx=\(ev.scrollingDeltaX) dy=\(ev.scrollingDeltaY) accX=\(swipeAccum) accY=\(swipeAccumY) phase=\(ev.phase.rawValue) exp=\(expanded) internal=\(scrollsInternally)\n".data(using: .utf8)!)
            }
            let vertical = abs(swipeAccumY) > abs(swipeAccum)
            if expanded {
                if !vertical, abs(swipeAccum) > 50 {
                    if coordinator.currentDroplet == .media {
                        if abs(swipeAccum) > 80 {
                            coordinator.media.send(swipeAccum > 0 ? .previousTrack : .nextTrack)
                            swipeFired = true
                        }
                    } else {
                        coordinator.requestPage(swipeAccum < 0 ? +1 : -1)
                        swipeFired = true
                    }
                } else if vertical, !scrollsInternally, abs(swipeAccumY) > 40, coordinator.config.verticalGestures {
                    coordinator.requestPage(swipeAccumY > 0 ? +1 : -1)
                    swipeFired = true
                } else if scrollsInternally {
                    return ev
                }
            } else {
                if !vertical, abs(swipeAccum) > 80 {
                    coordinator.media.send(swipeAccum > 0 ? .previousTrack : .nextTrack)
                    swipeFired = true
                } else if vertical, swipeAccumY > 40, coordinator.config.verticalGestures {
                    let hasMedia = !coordinator.media.nowPlaying.title.isEmpty
                    let searchEnabled = Droplet.pages(enabled: coordinator.config.enabledDroplets,
                                                      hasMedia: hasMedia).contains(.search)
                    switch PullDownRoute.target(opensSearch: coordinator.config.pullDownOpensSearch,
                                                searchEnabled: searchEnabled) {
                    case .search: coordinator.requestShowDroplet(.search)
                    case .expand: coordinator.requestExpand(true)
                    }
                    swipeFired = true
                }
            }
            if swipeFired, ev.phase == [] {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(350))
                    self?.swipeAccum = 0; self?.swipeAccumY = 0; self?.swipeFired = false
                }
            }
            return nil
        }
        coordinator.$config
            .map(\.hideInFullscreen)
            .removeDuplicates()
            .sink { [weak self] on in self?.updateFullscreenTimer(enabled: on) }
            .store(in: &cancellables)
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload() }
        }
        wsnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload() }
        }
        coordinator.$isExpanded.merge(with: coordinator.$showActions, coordinator.$dragActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMousePassthrough() }
            .store(in: &cancellables)
        LockScreenBridge.dlog("bridge \(LockScreenBridge.isAvailable ? "disponível" : "INDISPONÍVEL (SkyLight não carregou)")")
        coordinator.$isScreenLocked.removeDuplicates()
            .map { [weak coordinator] locked in
                (locked: locked, wasExpanded: locked && (coordinator?.isExpanded ?? false))
            }
            .combineLatest(coordinator.$config.map(\.showOnLockScreen).removeDuplicates())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lock, enabled in
                self?.applyLockScreenState(locked: lock.locked, enabled: enabled, wasExpanded: lock.wasExpanded)
            }
            .store(in: &cancellables)
    }

    private var desiredLevel: NSWindow.Level {
        if loweredLevelCount > 0 { return .floating }
        return draggingLevel ? Self.dragLevel : .screenSaver
    }

    private func applyLevel() {
        guard !lockScreenActive else { return }
        let lvl = desiredLevel
        panels.values.forEach { if $0.level != lvl { $0.level = lvl } }
    }

    private func applyLockScreenState(locked: Bool, enabled: Bool, wasExpanded: Bool) {
        if NotchCoordinator.previewLock {
            if locked { syncLockWidgets(bridge: nil) } else { dismissLockWidgets() }
            return
        }
        let want = LockScreenPolicy.shouldDelegate(locked: locked, enabled: enabled,
                                                   bridgeAvailable: LockScreenBridge.isAvailable)
        guard want != lockScreenActive, let bridge = LockScreenBridge.shared else { return }
        lockScreenActive = want
        LockScreenBridge.dlog("\(want ? "delegando" : "desdelegando") \(panels.count) painel(is) — locked=\(locked) enabled=\(enabled) wasExpanded=\(wasExpanded)")
        if want {
            hiddenBeforeLock = hiddenForFullscreen
            hiddenForFullscreen.removeAll()
            for panel in panels.values {
                panel.alphaValue = 1
                panel.ignoresMouseEvents = true
            }
            _ = wasExpanded
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, lockScreenActive else { return }
                panels.values.forEach { bridge.delegate($0) }
                syncLockWidgets(bridge: bridge)
            }
        } else {
            dismissLockWidgets()
            for panel in panels.values {
                bridge.undelegate(panel)
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
            if coordinator.config.hideInFullscreen {
                for (id, hidden) in hiddenBeforeLock where hidden {
                    guard let panel = panels[id] else { continue }
                    panel.alphaValue = 0
                    hiddenForFullscreen[id] = true
                }
            }
            hiddenBeforeLock.removeAll()
            unlockGraceUntil = Date().addingTimeInterval(0.6)
            applyLevel()
            updateMousePassthrough()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !lockScreenActive else { return }
                checkFullscreen()
            }
        }
    }

    private func syncLockWidgets(bridge: LockScreenBridge?) {
        let screens = NSScreen.screens.filter { panels[$0.coveDisplayID] != nil }
        guard !screens.isEmpty else { return }
        if lockWidgets == nil { lockWidgets = LockWidgetsController(coordinator: coordinator) }
        lockWidgets?.present(on: screens, bridge: bridge)
    }

    private func dismissLockWidgets() {
        lockWidgets?.dismiss()
        lockWidgets = nil
    }

    private func frontmostIsFullscreen(on screen: NSScreen) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let width = b["Width"] ?? 0, height = b["Height"] ?? 0
            if abs(width - screen.frame.width) < 2 && abs(height - screen.frame.height) < 2 {
                return true
            }
        }
        return false
    }

    private func updateFullscreenTimer(enabled: Bool) {
        guard enabled else {
            fullscreenTimer?.invalidate()
            fullscreenTimer = nil
            hiddenBeforeLock.removeAll()
            guard !hiddenForFullscreen.isEmpty else { return }
            hiddenForFullscreen.removeAll()
            panels.values.forEach { $0.alphaValue = 1 }
            return
        }
        guard fullscreenTimer == nil else { return }
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkFullscreen() }
        }
    }

    private func checkFullscreen() {
        guard !lockScreenActive else { return }
        guard Date() >= unlockGraceUntil else { return }
        for screen in NSScreen.screens {
            let id = screen.coveDisplayID
            guard let panel = panels[id] else { continue }
            let hide = coordinator.config.hideInFullscreen && frontmostIsFullscreen(on: screen)
            guard hide != (hiddenForFullscreen[id] ?? false) else { continue }
            hiddenForFullscreen[id] = hide
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = hide ? 0 : 1
            }
        }
    }

    private func currentSignature() -> String {
        let screens = ScreenSignature.make(NSScreen.screens.map { s in
            (id: s.coveDisplayID, frame: s.frame, notch: Self.notchRect(on: s).rect)
        })
        let overrides = coordinator.config.displayOverrides
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return "\(screens)#\(coordinator.config.displayOn)#\(overrides)#\(coordinator.config.simulatedNotchOnExternal)"
    }

    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    static func notchRect(on screen: NSScreen) -> (rect: NSRect, simulated: Bool) {
        let f = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let rect = NSRect(x: f.minX + left.maxX, y: f.maxY - screen.safeAreaInsets.top,
                              width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            return (rect, false)
        }
        let w: CGFloat = 220, h: CGFloat = 32
        return (NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h), true)
    }

    func pushLoweredLevel() {
        loweredLevelCount += 1
        if loweredLevelCount == 1 { applyLevel() }
    }

    static let dragLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
    private var draggingLevel = false
    func setDragLevel(_ on: Bool) {
        guard on != draggingLevel else { return }
        draggingLevel = on
        guard loweredLevelCount == 0 else { return }
        applyLevel()
    }

    func popLoweredLevel() {
        guard loweredLevelCount > 0 else { return }
        loweredLevelCount -= 1
        if loweredLevelCount == 0 { applyLevel() }
    }

    func reload() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let sig = currentSignature()
            guard sig != lastSignature else { return }
            hide()
            show()
        }
    }

    func applySharing() {
        let hide = coordinator.config.hideFromCapture
        panels.values.forEach { $0.sharingType = hide ? .none : .readOnly }
        lockWidgets?.applySharing(hide: hide)
    }

    private func wantsPanel(on screen: NSScreen) -> Bool {
        let builtin = screen.safeAreaInsets.top > 0
        let uuid = DisplayIdentity.current(for: screen.coveDisplayID).uuid
        return DisplayPolicy.wantsPanel(uuid: uuid, isBuiltin: builtin,
                                         global: coordinator.config.displayOn,
                                         overrides: coordinator.config.displayOverrides)
    }

    func show() {
        lastDragCount = NSPasteboard(name: .drag).changeCount
        if mouseMonitor == nil {
            let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: kinds) { [weak self] ev in
                Task { @MainActor in self?.handleGlobalMouse(ev) }
            }
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] ev in
                Task { @MainActor in self?.updateMousePassthrough() }
                return ev
            }
        }
        let candidateScreens = NSScreen.screens.filter(wantsPanel(on:))
        let primaryDisplayID = candidateScreens.first(where: { $0.safeAreaInsets.top > 0 })?.coveDisplayID
            ?? candidateScreens.first?.coveDisplayID
        for screen in NSScreen.screens {
            guard wantsPanel(on: screen) else { continue }
            let displayID = screen.coveDisplayID
            let (notch, simulated) = Self.notchRect(on: screen)
            if simulated, !coordinator.config.simulatedNotchOnExternal { continue }
            let panelW = Self.panelSize.width, panelH = Self.panelSize.height
            let frame = NSRect(x: notch.midX - panelW / 2, y: notch.maxY - panelH,
                               width: panelW, height: panelH)
            let panel = KeyablePanel(contentRect: frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = desiredLevel
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.hasShadow = false
            panel.isMovable = false
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
            let hosting = NSHostingView(rootView: NotchView(
                coordinator: coordinator, notchSize: notch.size, simulated: simulated,
                displayID: displayID, isPrimary: displayID == primaryDisplayID))
            hosting.frame = container.bounds
            hosting.autoresizingMask = [.width, .height]
            container.addSubview(hosting)
            let host = DropHostView(frame: container.bounds)
            host.autoresizingMask = [.width, .height]
            host.isDragActive = { [weak self] in self?.coordinator.dragActive ?? false }
            container.addSubview(host, positioned: .above, relativeTo: hosting)
            panel.contentView = container
            panel.registerForDraggedTypes([.fileURL])
            host.onDrop = { [weak self] urls in self?.coordinator.handleFileDrop(urls) }
            host.onDragEnter = { [weak self] in
                guard let self else { return }
                if !(coordinator.isExpanded && coordinator.currentDroplet == .converter) {
                    coordinator.requestShowDroplet(.shelf)
                }
            }
            host.isInsideIsland = { [weak self, weak host] p in
                guard let self, let host else { return true }
                let f = coordinator.islandFrames[displayID] ?? .zero
                guard f != .zero else { return true }
                let flipped = CGPoint(x: p.x, y: host.bounds.height - p.y)
                return f.contains(flipped)
            }
            panel.ignoresMouseEvents = ProcessInfo.processInfo.environment["COVE_NOPASS"] == nil
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            if lockScreenActive, let bridge = LockScreenBridge.shared {
                panel.ignoresMouseEvents = true
                bridge.delegate(panel)
            }
            panels[displayID] = panel
        }
        applySharing()
        lastSignature = currentSignature()
        if lockScreenActive {
            syncLockWidgets(bridge: LockScreenBridge.shared)
        } else if NotchCoordinator.previewLock, coordinator.isScreenLocked {
            syncLockWidgets(bridge: nil)
        }
    }

    func hide() {
        dismissLockWidgets()
        if lockScreenActive, let bridge = LockScreenBridge.shared {
            panels.values.forEach { bridge.undelegate($0) }
        }
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        hiddenForFullscreen.removeAll()
        hiddenBeforeLock.removeAll()
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
        dragPollTask?.cancel(); dragPollTask = nil
    }

    private func islandContains(screenPoint: NSPoint, id: CGDirectDisplayID, panel: NSPanel) -> Bool {
        guard panel.frame.contains(screenPoint) else { return false }
        guard let f = coordinator.islandFrames[id], f != .zero else { return true }
        let p = panel.convertPoint(fromScreen: screenPoint)
        let flipped = CGPoint(x: p.x, y: (panel.contentView?.bounds.height ?? Self.panelSize.height) - p.y)
        return f.insetBy(dx: -12, dy: -12).contains(flipped)
    }

    func updateMousePassthrough() {
        if ProcessInfo.processInfo.environment["COVE_NOPASS"] != nil { return }
        if lockScreenActive {
            panels.values.forEach { if !$0.ignoresMouseEvents { $0.ignoresMouseEvents = true } }
            return
        }
        let loc = NSEvent.mouseLocation
        let keep = coordinator.dragActive || coordinator.isExpanded || coordinator.showActions
        for (id, panel) in panels {
            let wants = keep || islandContains(screenPoint: loc, id: id, panel: panel)
            if panel.ignoresMouseEvents == wants { panel.ignoresMouseEvents = !wants }
        }
    }

    private func handleGlobalMouse(_ ev: NSEvent) {
        switch ev.type {
        case .leftMouseDown:
            DropHostView.dlog("mouseDown loc=\(NSEvent.mouseLocation) dragCount=\(NSPasteboard(name: .drag).changeCount) last=\(lastDragCount)")
            dragPollTask?.cancel()
            dragPollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled, NSEvent.pressedMouseButtons & 1 == 1 {
                    self?.pollDrag()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        case .leftMouseUp:
            dragPollTask?.cancel(); dragPollTask = nil
            lastDragCount = NSPasteboard(name: .drag).changeCount
            if coordinator.dragActive {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(600))
                    self?.coordinator.dragActive = false
                    self?.setDragLevel(false)
                    self?.updateMousePassthrough()
                }
            }
        default:
            updateMousePassthrough()
        }
    }

    private func pollDrag() {
        let pb = NSPasteboard(name: .drag)
        DropHostView.dlog("poll count=\(pb.changeCount) last=\(lastDragCount) file=\(pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])) active=\(coordinator.dragActive)")
        guard pb.changeCount != lastDragCount,
              pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
        if !coordinator.dragActive {
            coordinator.dragActive = true
            DropHostView.dlog("drag de arquivo detectado (changeCount \(pb.changeCount))")
            setDragLevel(true)
        }
        guard !lockScreenActive else { return }
        for panel in panels.values where panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
        let loc = NSEvent.mouseLocation
        if ProcessInfo.processInfo.environment["COVE_NOJIGGLE"] == nil,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(loc) }),
           screen.frame.maxY - loc.y < 60,
           !(coordinator.isExpanded && coordinator.currentDroplet == .converter) {
            coordinator.requestShowDroplet(.shelf)
        }
    }

    private func keyCandidatePanel() -> NSPanel? {
        if let id = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.coveDisplayID,
           let panel = panels[id] {
            return panel
        }
        if coordinator.isExpanded, let id = currentExpandedDisplayID, let panel = panels[id] {
            return panel
        }
        return panels.values.first
    }

    private var currentExpandedDisplayID: CGDirectDisplayID? {
        NSScreen.screens.first { screen in
            let id = screen.coveDisplayID
            guard let panel = panels[id] else { return false }
            return panel.isKeyWindow
        }?.coveDisplayID
    }

    func makeKey() {
        keyCandidatePanel()?.makeKey()
    }

    func resignKey() {
        keyCandidatePanel()?.resignKey()
    }
}
