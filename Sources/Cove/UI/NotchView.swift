import SwiftUI

struct NotchShape: Shape {
    var bottomRadius: CGFloat = 12
    var topRadius: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set { bottomRadius = newValue.first; topRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = bottomRadius
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: t, y: t), control: CGPoint(x: t, y: 0))
        p.addLine(to: CGPoint(x: t, y: h - b))
        p.addQuadCurve(to: CGPoint(x: t + b, y: h), control: CGPoint(x: t, y: h))
        p.addLine(to: CGPoint(x: w - t - b, y: h))
        p.addQuadCurve(to: CGPoint(x: w - t, y: h - b), control: CGPoint(x: w - t, y: h))
        p.addLine(to: CGPoint(x: w - t, y: t))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - t, y: 0))
        p.closeSubpath()
        return p
    }
}

struct NotchView: View {
    @ObservedObject var coordinator: NotchCoordinator
    let notchSize: CGSize
    let simulated: Bool
    let displayID: CGDirectDisplayID
    let isPrimary: Bool

    private let previewLock = ProcessInfo.processInfo.environment["COVE_PREVIEW_EXPANDED"] == "1"
    @State private var expanded = ProcessInfo.processInfo.environment["COVE_PREVIEW_EXPANDED"] == "1"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morph
    @State private var hoverTask: Task<Void, Never>?
    @State private var outsideClickMonitor: Any?
    @State private var pressStartedOnActivity = false
    @State private var page = Int(ProcessInfo.processInfo.environment["COVE_PREVIEW_PAGE"] ?? "") ?? 0
    @State private var openLockGrace = false
    @State private var openLockTask: Task<Void, Never>?

    private var media: MediaRemoteService { coordinator.media }
    private var hasMedia: Bool { !media.nowPlaying.title.isEmpty }
    private var showWings: Bool { hasMedia && media.nowPlaying.isPlaying && !coordinator.isScreenLocked }
    private var lockResting: Bool { coordinator.isScreenLocked || openLockGrace }
    private var pages: [Droplet] { Droplet.pages(enabled: coordinator.config.enabledDroplets, hasMedia: hasMedia) }
    private var currentDroplet: Droplet { pages[min(page, pages.count - 1)] }
    private func lockSafe(_ a: NotchActivity) -> NotchActivity {
        coordinator.isScreenLocked ? a.redactedForLockScreen : a
    }
    private var leadingPeek: NotchActivity? { coordinator.leadingActivity.map(lockSafe) }
    private var trailingPeek: NotchActivity? {
        (coordinator.trailingActivity ?? coordinator.ambientActivity).map(lockSafe)
    }
    private var canExpand: Bool { true }
    private var peek: NotchActivity? { trailingPeek ?? leadingPeek }
    private var transientPeek: NotchActivity? { coordinator.trailingActivity ?? coordinator.leadingActivity }
    private var wideContent: WideIslandContent? {
        guard !expanded, transientPeek == nil, !lockResting,
              WideIslandLayout.isWide(mode: coordinator.config.wideIsland, simulated: simulated)
        else { return nil }
        return WideIslandContent.pick(media: showWings, activity: coordinator.ambientActivity.map(lockSafe))
    }

    var body: some View {
        VStack(spacing: 0) {
            island
                .task {
                    guard ProcessInfo.processInfo.environment["COVE_PREVIEW_PULSE"] == "1" else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1.5))
                        let opening = !expanded
                        withAnimation(opening
                            ? .spring(duration: 0.26, bounce: 0.22)
                            : .spring(duration: 0.34, bounce: 0.0)) {
                            expanded = opening
                        }
                    }
                }
                .onHover { over in
                    guard !previewLock, coordinator.config.expandOnHover else { return }
                    guard !coordinator.isScreenLocked else { return }
                    guard !coordinator.showActivityExpanded else { return }
                    guard !coordinator.dragActive else { return }
                    hoverTask?.cancel()
                    let opening = over && canExpand
                    guard opening != expanded else { return }
                    let delay = opening ? coordinator.config.hoverDuration : 0.05
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(delay))
                        guard !Task.isCancelled, !(opening && coordinator.isScreenLocked) else { return }
                        if coordinator.config.hapticFeedback {
                            NSHapticFeedbackManager.defaultPerformer
                                .perform(.alignment, performanceTime: .now)
                        }
                        withAnimation(opening
                            ? .spring(duration: 0.26, bounce: 0.22)
                            : .spring(duration: 0.34, bounce: 0.0)) {
                            expanded = opening
                        }
                    }
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.hudStyle, coordinator.config.hudStyle)
        .environment(\.dynamicGlass, coordinator.config.dynamicGlass)
        .environment(\.dynamicGlassTint, coordinator.config.dynamicGlassTint)
        .environment(\.colorScheme, .dark)
        .onChange(of: coordinator.expandRequest) {
            guard let req = coordinator.expandRequest, !previewLock,
                  req.targets(displayID: displayID, primary: isPrimary) else { return }
            setExpanded(req.value)
        }
        .onChange(of: coordinator.isScreenLocked) {
            openLockTask?.cancel()
            guard coordinator.isScreenLocked else {
                openLockGrace = true
                openLockTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    openLockGrace = false
                }
                return
            }
            openLockGrace = false
            hoverTask?.cancel()
            setExpanded(false)
        }
        .onChange(of: coordinator.config.enabledDroplets) { oldValue, _ in
            let oldPages = Droplet.pages(enabled: oldValue, hasMedia: hasMedia)
            let oldDroplet = page >= 0 && page < oldPages.count ? oldPages[page] : nil
            page = oldDroplet.flatMap { pages.firstIndex(of: $0) } ?? 0
        }
        .onChange(of: coordinator.pageRequest) {
            guard let req = coordinator.pageRequest,
                  req.targets(displayID: displayID, primary: isPrimary) else { return }
            let d = req.value
            let last = pages.count - 1
            let next = page + d
            if next < 0 || (next > last && d > 0 && page == last) {
                setExpanded(false)
            } else {
                withAnimation(.spring(duration: 0.3, bounce: 0.18)) { page = min(max(next, 0), last) }
            }
        }
        .onChange(of: coordinator.showDropletRequest) {
            guard let req = coordinator.showDropletRequest,
                  req.targets(displayID: displayID, primary: isPrimary) else { return }
            let d = req.value
            if !expanded { setExpanded(true) }
            if let i = pages.firstIndex(of: d) {
                withAnimation(.spring(duration: 0.3, bounce: 0.18)) { page = i }
            }
        }
        .onChange(of: expanded, initial: true) {
            coordinator.isExpanded = expanded
            if !expanded {
                page = 0
                coordinator.showActions = false
                coordinator.closeActivityExpanded()
            }
            coordinator.currentDroplet = activePageDroplet
        }
        .onChange(of: page, initial: true) {
            coordinator.currentDroplet = activePageDroplet
        }
        .onChange(of: coordinator.showActivityExpanded) {
            coordinator.currentDroplet = activePageDroplet
            updateOutsideClickMonitor()
        }
        .onDisappear { removeOutsideClickMonitor() }
    }

    private func setExpanded(_ open: Bool) {
        guard open != expanded, !open || canExpand else { return }
        guard !open || !coordinator.isScreenLocked else { return }
        if coordinator.config.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        coordinator.isExpanded = open
        withAnimation(open ? .spring(duration: 0.26, bounce: 0.22)
                           : .spring(duration: 0.34, bounce: 0.0)) {
            expanded = open
        }
    }

    private var dualIsland: Bool { false }

    private var openHUD: NotchActivity? {
        guard expanded, let a = coordinator.activity, a.isHUD else { return nil }
        return a
    }

    @ViewBuilder private var island: some View {
        VStack(spacing: 8) {
            mainIsland
            if let hud = openHUD {
                FloatingHUDPill(activity: hud)
                    .environment(\.hudStyle, HUDStyleResolver.style(
                        for: hud.kindKey, styles: coordinator.config.hudStyles, fallback: coordinator.config.hudStyle))
                    .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.26, bounce: 0.22), value: openHUD == nil)
        .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.2), value: expanded)
        .animation(reduceMotion ? nil : (leadingPeek != nil
            ? .spring(duration: 0.32, bounce: 0.30) : .spring(duration: 0.26, bounce: 0)), value: leadingPeek)
        .animation(reduceMotion ? nil : (trailingPeek != nil
            ? .spring(duration: 0.32, bounce: 0.30) : .spring(duration: 0.26, bounce: 0)), value: trailingPeek)
        .animation(reduceMotion ? nil : (wideContent != nil
            ? .spring(duration: 0.32, bounce: 0.30) : .spring(duration: 0.26, bounce: 0)),
            value: wideContent?.animationKey)
        .animation(reduceMotion ? nil : (showWings
            ? .spring(duration: 0.32, bounce: 0.30) : .spring(duration: 0.26, bounce: 0)),
            value: showWings)
        .animation(reduceMotion ? nil : (lockResting
            ? .spring(duration: 0.32, bounce: 0.30) : .spring(duration: 0.26, bounce: 0)),
            value: lockResting)
    }

    private var isWiderThanNotch: Bool {
        expanded || (peek != nil && !showWings) || showWings || lockResting || simulated
    }

    private var expandedHeight: CGFloat {
        (currentDroplet == .media && !coordinator.showActivityExpanded)
            ? 175 + (simulated ? 0 : max(0, notchSize.height - 30))
            : 170 + (simulated ? 0 : notchSize.height + 6)
    }

    private var flare: CGFloat { expanded ? 24 : 10 }

    private var shape: NotchShape {
        NotchShape(
            bottomRadius: expanded ? 40 : (peek != nil && !dualIsland ? 18 : (simulated ? 14 : 12)),
            topRadius: flare)
    }

    @ViewBuilder private var mainIsland: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black)

            if expanded {
                VStack(spacing: 4) {
                    Group {
                        if coordinator.showActivityExpanded, let a = coordinator.expandedActivity {
                            ActivityExpandedView(coordinator: coordinator, activity: a,
                                                 notchTop: simulated ? 4 : notchSize.height + 6)
                        } else if coordinator.showActions {
                            ActionsOverlay(coordinator: coordinator, notchTop: simulated ? 4 : notchSize.height + 6)
                        } else {
                            dropletPage(currentDroplet)
                        }
                    }
                    .padding(.horizontal, flare)
                    .frame(maxHeight: .infinity)
                    .clipped()
                    .id(coordinator.showActivityExpanded ? "activity"
                        : (coordinator.showActions ? "actions" : "\(currentDroplet)"))
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
                    if !coordinator.showActions, !coordinator.showActivityExpanded,
                       pages.count > 1, currentDroplet != .media {
                        PageBar(pages: pages, current: page) { i in
                            withAnimation(.spring(duration: 0.3, bounce: 0.18)) { page = i }
                        }
                        .padding(.bottom, 6)
                    }
                }
                .frame(height: expandedHeight)
                .overlay(alignment: .bottom) {
                    if !coordinator.showActions, !coordinator.showActivityExpanded,
                       pages.count > 1, currentDroplet == .media {
                        PageBar(pages: pages, current: page) { i in
                            withAnimation(.spring(duration: 0.3, bounce: 0.18)) { page = i }
                        }
                        .padding(.bottom, 3)
                    }
                }
            } else if let p = peek, isTrackPeek(p), showWings {
                MediaWings(media: media, waveform: coordinator.waveform, morph: morph,
                           height: notchSize.height, titled: true)
                    .padding(.horizontal, flare)
                    .transition(.blurReplace)
            } else if let w = wideContent {
                WideIslandView(content: w, media: media, waveform: coordinator.waveform, morph: morph,
                               height: notchSize.height, notchWidth: notchSize.width, simulated: simulated)
                    .padding(.horizontal, flare)
                    .transition(.blurReplace)
            } else if let p = peek {
                PeekView(activity: p, notchWidth: notchSize.width, height: notchSize.height)
                    .environment(\.hudStyle, HUDStyleResolver.style(
                        for: p.kindKey, styles: coordinator.config.hudStyles, fallback: coordinator.config.hudStyle))
                    .padding(.horizontal, flare)
                    .transition(AnyTransition.asymmetric(
                        insertion: AnyTransition(.blurReplace).combined(with: .scale(scale: 0.85))
                            .animation(.spring(duration: 0.3, bounce: 0.2).delay(0.05)),
                        removal: AnyTransition(.blurReplace).animation(.easeOut(duration: 0.15))))
            } else if lockResting {
                LockWing(open: !coordinator.isScreenLocked, height: notchSize.height)
                    .padding(.horizontal, flare)
                    .transition(.blurReplace)
            } else if showWings {
                MediaWings(media: media, waveform: coordinator.waveform, morph: morph,
                           height: notchSize.height)
                    .padding(.horizontal, flare)
                    .transition(.blurReplace)
            }
        }
        .frame(width: currentWidth + flare * 2, height: expanded ? expandedHeight : notchSize.height)
        .clipShape(shape)
        .compositingGroup()
        .shadow(color: expanded ? .black.opacity(0.6) : .clear, radius: expanded ? 22 : 0, y: expanded ? 10 : 0)
        .contentShape(shape)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { coordinator.islandFrames[displayID] = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) {
                    coordinator.islandFrames[displayID] = g.frame(in: .global)
                    if ProcessInfo.processInfo.environment["COVE_DEBUG"] != nil {
                        FileHandle.standardError.write("[island] \(displayID) frame=\(g.frame(in: .global)) expanded=\(expanded)\n".data(using: .utf8)!)
                    }
                }
                .onDisappear { coordinator.islandFrames[displayID] = nil }
        })
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onChanged { _ in
                    pressStartedOnActivity = !previewLock
                        && coordinator.config.expandActivityOnLongPress
                        && !coordinator.showActivityExpanded
                        && !coordinator.showActions
                        && coordinator.activityForExpansion != nil
                }
                .onEnded { _ in
                    guard pressStartedOnActivity else { return }
                    pressStartedOnActivity = false
                    hoverTask?.cancel()
                    coordinator.requestActivityExpanded()
                }
        )
        .onTapGesture {
            pressStartedOnActivity = false
            if coordinator.showActivityExpanded { coordinator.cancelActivityExpandedDismiss(); return }
            if let a = peek, !expanded {
                if case .event = a { NotchActions.openCalendar(); return }
                if case .eventCountdown(_, _, let meetingURL) = a {
                    if coordinator.config.hapticFeedback {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    if let meetingURL { NSWorkspace.shared.open(meetingURL) } else { NotchActions.openCalendar() }
                    return
                }
                if case .recording = a { coordinator.requestShowDroplet(.tools); return }
                if case .timer = a { coordinator.requestShowDroplet(.tools); return }
                if case .screenRecording = a { coordinator.requestShowDroplet(.tools); return }
            }
            setExpanded(!expanded)
        }
    }

    @ViewBuilder private func dropletPage(_ d: Droplet) -> some View {
        let top = simulated ? 4 : notchSize.height + 6
        switch d {
        case .media: ExpandedMediaCard(coordinator: coordinator, morph: morph, notchTop: top)
        case .apps: AppsPage(coordinator: coordinator, notchTop: top)
        case .shelf: ShelfPage(shelf: coordinator.shelf, notchTop: top)
        case .clipboard: ClipboardPage(store: coordinator.clipboard, linkPreviews: coordinator.linkPreviews, coordinator: coordinator, notchTop: top)
        case .tools: ToolsPage(coordinator: coordinator, notchTop: top)
        case .search: SearchPage(coordinator: coordinator, notchTop: top)
        case .terminal:
            TerminalPage(notchTop: top)
                .onAppear { NotchPanelController.current?.makeKey() }
                .onDisappear { NotchPanelController.current?.resignKey() }
        case .notifications: NotificationsPage(mirror: coordinator.notifications, notchTop: top)
        case .stats: StatsPage(stats: coordinator.systemStats, notchTop: top)
        case .notes: NotesPage(store: coordinator.notesStore, notchTop: top)
        case .converter: ConverterPage(converter: coordinator.converter, coordinator: coordinator, notchTop: top)
        case .emoji: EmojiPage(store: coordinator.emojiStore, coordinator: coordinator, notchTop: top)
        }
    }

    private var activePageDroplet: Droplet? {
        guard expanded, !coordinator.showActivityExpanded else { return nil }
        return currentDroplet
    }

    private func updateOutsideClickMonitor() {
        if coordinator.showActivityExpanded {
            guard outsideClickMonitor == nil else { return }
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]) { _ in
                Task { @MainActor in coordinator.closeActivityExpanded() }
            }
        } else {
            removeOutsideClickMonitor()
        }
    }

    private func removeOutsideClickMonitor() {
        guard let m = outsideClickMonitor else { return }
        NSEvent.removeMonitor(m)
        outsideClickMonitor = nil
    }

    private func isTrackPeek(_ a: NotchActivity) -> Bool {
        if case .track = a { return true }
        return false
    }

    private var currentWidth: CGFloat {
        if expanded { return 400 }
        if let p = peek, isTrackPeek(p), showWings { return notchSize.width + 76 + 150 }
        if wideContent != nil {
            return (showWings ? notchSize.width + 76 : notchSize.width) + WideIslandLayout.extraWidth
        }
        if peek != nil { return notchSize.width + 2 * PeekView.wing }
        if lockResting { return notchSize.width + 76 }
        return showWings ? notchSize.width + 76 : notchSize.width
    }
}

private struct LockWing: View {
    let open: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: open ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 12)
                .contentTransition(.symbolEffect(.replace))
            Spacer(minLength: 0)
        }
        .frame(height: height)
    }
}

private struct WideIslandView: View {
    let content: WideIslandContent
    @ObservedObject var media: MediaRemoteService
    var waveform: WaveformService?
    let morph: Namespace.ID
    let height: CGFloat
    let notchWidth: CGFloat
    let simulated: Bool

    var body: some View {
        switch content {
        case .media:
            MediaWings(media: media, waveform: waveform, morph: morph, height: height, titled: true)
        case .activity(let a):
            HStack(spacing: 8) {
                icon(a)
                Text(WideIslandLayout.label(for: a))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: simulated ? 0 : notchWidth)
                value(a)
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .frame(height: height)
        case .mediaAndActivity(let a):
            HStack(spacing: 8) {
                ArtworkThumb(media: media, size: height - 10)
                    .matchedGeometryEffect(id: "artwork", in: morph)
                    .padding(.leading, 7)
                Spacer(minLength: simulated ? 0 : notchWidth)
                icon(a)
                value(a)
                    .padding(.trailing, 12)
            }
            .frame(height: height)
        }
    }

    @ViewBuilder private func icon(_ a: NotchActivity) -> some View {
        let r = ActivityExpansion.regions(for: a)
        Image(systemName: r.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(WideIslandView.color(r.tint))
    }

    @ViewBuilder private func value(_ a: NotchActivity) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(WideIslandView.valueText(a, now: ctx.date))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
    }

    static func valueText(_ a: NotchActivity, now: Date) -> String {
        if case .eventCountdown(_, let start, _) = a {
            return ActivityExpansion.mmss(Int(start.timeIntervalSince(now)))
        }
        return ActivityExpansion.regions(for: a, context: .init(now: now)).value ?? ""
    }

    static func color(_ t: ActivityExpansion.Tint) -> Color {
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

private struct MediaWings: View {
    @ObservedObject var media: MediaRemoteService
    var waveform: WaveformService?
    let morph: Namespace.ID
    let height: CGFloat
    var titled = false

    var body: some View {
        HStack(spacing: 8) {
            ArtworkThumb(media: media, size: height - 10)
                .matchedGeometryEffect(id: "artwork", in: morph)
                .padding(.leading, 7)
            if titled {
                VStack(alignment: .leading, spacing: 0) {
                    Text(media.nowPlaying.title).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(media.nowPlaying.artist).font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
                .transition(.blurReplace)
            }
            Spacer()
            wing
                .padding(.trailing, 12)
        }
        .frame(height: height)
    }

    private var tint: Color {
        media.nowPlaying.artworkTint.map(Color.init) ?? .white
    }

    @ViewBuilder private var wing: some View {
        if let waveform, waveform.running, media.nowPlaying.isPlaying {
            LiveWaveform(waveform: waveform, tint: tint)
        } else if media.nowPlaying.isPlaying {
            EqualizerGlyph(tint: tint.opacity(0.85), animated: true)
        } else {
            EqualizerGlyph(tint: .white.opacity(0.45), animated: false)
        }
    }
}

private struct EqualizerGlyph: View {
    let tint: Color
    let animated: Bool

    private static let bases: [CGFloat] = [11, 7, 3, 7, 11]

    private func barHeight(index i: Int, time t: TimeInterval) -> CGFloat {
        guard animated else { return 2.5 }
        let base: CGFloat = Self.bases[i]
        let phase: Double = t * (5.0 + Double(i) * 1.7) + Double(i)
        let wobble: CGFloat = CGFloat(sin(phase)) * 3.0
        return max(2.5, base + wobble)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !animated)) { ctx in
            let t: TimeInterval = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(tint)
                        .frame(width: 2.5, height: barHeight(index: i, time: t))
                }
            }
            .animation(.spring(duration: 0.22, bounce: 0.35), value: animated)
        }
        .frame(width: 22, height: 16)
    }
}

private struct LiveWaveform: View {
    @ObservedObject var waveform: WaveformService
    var tint: Color = .white

    private let order = [4, 2, 0, 1, 3]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                let level = CGFloat(waveform.levels[order[i]])
                let emphasis: CGFloat = i == 2 ? 1.0 : (i == 1 || i == 3 ? 0.8 : 0.55)
                Capsule()
                    .fill(tint.opacity(0.95))
                    .frame(width: 2.5, height: max(3, 3 + level * 13 * emphasis))
                    .animation(.spring(duration: 0.28, bounce: 0.45)
                        .delay(Double(abs(i - 2)) * 0.02), value: waveform.levels)
            }
        }
        .frame(height: 18)
    }
}

private struct PeekView: View {
    let activity: NotchActivity
    let notchWidth: CGFloat
    let height: CGFloat

    static let wing: CGFloat = 150

    var body: some View {
        HStack(spacing: 0) {
            PeekIcon(activity: activity)
                .font(.system(size: 14, weight: .semibold))
                .padding(.leading, 12)
                .frame(width: Self.wing, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            PeekTrailing(activity: activity)
                .padding(.trailing, 14)
                .frame(width: Self.wing, alignment: .trailing)
        }
        .frame(height: height)
    }
}

struct PeekIcon: View {
    let activity: NotchActivity

    var body: some View { icon }

    @ViewBuilder private var icon: some View {
        switch activity {
        case .volume(_, let muted):
            HStack(spacing: 8) {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(muted ? "Mudo" : "Som")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .fixedSize()
        case .brightness:
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Brilho")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .fixedSize()
        case .keyboardBrightness:
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 13, weight: .semibold))
                Text("Teclado")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .fixedSize()
        case .battery(let s):
            Image(systemName: s.onAC ? "battery.100percent.bolt" : "battery.25percent")
                .foregroundStyle(s.onAC ? .green : (s.percent <= 20 ? .red : .white))
        case .lowPowerMode(let on):
            Image(systemName: "leaf.fill").foregroundStyle(on ? .yellow : .gray)
        case .device(let name, let connected, _):
            Image(systemName: DeviceSymbol.symbol(for: name, connected: connected))
                .foregroundStyle(connected ? .white : .gray)
        case .focus(let on):
            Image(systemName: on ? "moon.fill" : "moon")
                .foregroundStyle(on ? .purple : .gray)
        case .lock(let locked):
            Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                .foregroundStyle(.white)
        case .event, .eventCountdown:
            Image(systemName: "calendar").foregroundStyle(.red)
        case .notification:
            Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
        case .track:
            Image(systemName: "music.note").foregroundStyle(.white)
        case .timer:
            Image(systemName: "timer").foregroundStyle(.white)
        case .recording:
            Image(systemName: "mic.fill").foregroundStyle(.red)
        case .screenRecording:
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
        case .wifi(_, let connected):
            Image(systemName: connected ? "wifi" : "wifi.slash")
                .foregroundStyle(connected ? .white : .gray)
        case .hotspot(let on):
            Image(systemName: "personalhotspot")
                .foregroundStyle(on ? .white : .gray)
        case .drive(_, let mounted):
            Image(systemName: mounted ? "externaldrive.fill" : "externaldrive.badge.minus")
                .foregroundStyle(.white)
        case .vpn(let up):
            Image(systemName: up ? "lock.shield.fill" : "lock.open")
                .foregroundStyle(up ? .white : .gray)
        case .vpnSession:
            Image(systemName: "lock.shield.fill").foregroundStyle(.white)
        case .highAlert:
            Image(systemName: "bolt.fill").foregroundStyle(.yellow)
        }
    }

}

struct PeekTrailing: View {
    let activity: NotchActivity

    var body: some View { trailing }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case .volume(let v, let muted):
            LevelBar(level: muted ? 0 : v, tint: .white)
        case .brightness(let v), .keyboardBrightness(let v):
            HStack(spacing: 8) {
                LevelBar(level: v, tint: .white)
                Text("\(Int((v * 100).rounded()))")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .contentTransition(.numericText())
            }
        case .battery(let s):
            Text("\(s.percent)%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(s.onAC ? .green : (s.percent <= 20 ? .red : .white))
                .contentTransition(.numericText())
        case .lowPowerMode(let on):
            Text(on ? "Economia" : "Normal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        case .device(let name, let connected, let battery):
            Text(connected ? (battery.map { "\(name) · \($0)%" } ?? name) : "\(name) saiu")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        case .focus(let on):
            Text(on ? "Foco ativado" : "Foco desativado")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        case .lock(let locked):
            Text(locked ? "Bloqueado" : "Desbloqueado")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        case .event(let title, let minutes):
            Text("\(title) · \(minutes) min")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        case .eventCountdown(let title, let start, _):
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let remaining = start.timeIntervalSince(ctx.date)
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(remaining <= 0 ? "agora" : "em \(EventCountdown.minutesLabel(remaining)) min")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                        EventCountdown.Ring(progress: NotchActivity.eventCountdownProgress(now: ctx.date, start: start))
                            .frame(width: 14, height: 14)
                    }
                    Text(title).font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        case .notification(let app, let title):
            Text(title.isEmpty ? app : "\(app): \(title)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        case .track(let title, let artist):
            VStack(alignment: .trailing, spacing: 0) {
                Text(title).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text(artist).font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
        case .timer(let label, let remaining):
            HStack(spacing: 6) {
                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(label).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .recording(let elapsed):
            HStack(spacing: 6) {
                Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("Gravando").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .screenRecording(let elapsed):
            HStack(spacing: 6) {
                Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("Gravando tela").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .wifi(let ssid, let connected):
            Text(connected ? (ssid.map { "Conectado a \($0)" } ?? "Wi-Fi conectado") : "Wi-Fi desligado")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        case .hotspot(let on):
            Text(on ? "Hotspot ligado" : "Hotspot desligado")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        case .drive(let name, let mounted):
            Text(mounted ? "\(name) montado" : "\(name) ejetado")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        case .vpn(let up):
            Text(up ? "VPN conectada" : "VPN desconectada")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        case .vpnSession(let since):
            TimelineView(.periodic(from: since, by: 1)) { context in
                let elapsed = max(Int(context.date.timeIntervalSince(since)), 0)
                Text(String(format: "%02d:%02d", elapsed / 3600, (elapsed % 3600) / 60))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        case .highAlert(let expiresAt):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(Int(expiresAt.timeIntervalSince(context.date).rounded()), 0)
                HStack(spacing: 6) {
                    Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("High Alert").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

enum EventCountdown {
    static func minutesLabel(_ remaining: TimeInterval) -> Int {
        max(Int(remaining / 60) + (remaining.truncatingRemainder(dividingBy: 60) > 0 ? 1 : 0), 0)
    }

    struct Ring: View {
        let progress: Double
        var body: some View {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 2)
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    struct Row: View {
        let title: String
        let start: Date
        let meetingURL: URL?
        @ObservedObject var coordinator: NotchCoordinator

        var body: some View {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let remaining = start.timeIntervalSince(ctx.date)
                HStack(spacing: 10) {
                    Ring(progress: NotchActivity.eventCountdownProgress(now: ctx.date, start: start))
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                        Text(remaining <= 0 ? "agora" : "em \(minutesLabel(remaining)) min")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Button(meetingURL != nil ? "Entrar" : "Abrir") { act() }
                        .buttonStyle(NotchButtonStyle())
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }

        private func act() {
            if coordinator.config.hapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            if let meetingURL { NSWorkspace.shared.open(meetingURL) } else { NotchActions.openCalendar() }
        }
    }
}

private struct LevelBar: View {
    let level: Float
    let tint: Color
    var width: CGFloat? = 96
    @Environment(\.hudStyle) private var style

    private var fill: Color { style == "accent" ? Color(nsColor: .controlAccentColor) : tint }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(fill)
                    .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
                    .shadow(color: style == "glow" ? fill.opacity(0.9) : .clear, radius: 6)
            }
        }
        .frame(width: width, height: 6)
        .animation(.snappy(duration: 0.18), value: level)
    }
}

private struct ExpandedMediaCard: View {
    @ObservedObject var coordinator: NotchCoordinator
    let morph: Namespace.ID
    let notchTop: CGFloat

    private var media: MediaRemoteService { coordinator.media }
    private var hud: NotchActivity? {
        if let a = coordinator.activity, a.isHUD { return a }
        return nil
    }
    private var eventCountdown: NotchActivity? {
        if case .eventCountdown = coordinator.ambientActivity { return coordinator.ambientActivity }
        return nil
    }

    private var motionArtActive: Bool {
        coordinator.config.motionArt && media.nowPlaying.isPlaying && (coordinator.waveform?.running ?? false)
    }

    private var showLyrics: Bool {
        coordinator.config.lyricsEnabled && coordinator.lyrics.state == .found
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let waveform = coordinator.waveform {
                MotionArtView(waveform: waveform,
                              tint: media.nowPlaying.artworkTint.map(Color.init) ?? .white.opacity(0.3),
                              running: motionArtActive)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .opacity(motionArtActive ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: motionArtActive)
            }
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    ArtworkThumb(media: media, size: 50)
                        .matchedGeometryEffect(id: "artwork", in: morph)
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: media.nowPlaying.title,
                                    font: .system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(height: 18)
                        if showLyrics {
                            CurrentLyricLine(media: media, lyrics: coordinator.lyrics)
                        } else {
                            Text(media.nowPlaying.artist)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, max(0, notchTop - 20))
                    Spacer(minLength: 40)
                }
                .padding(.leading, 28)
                .padding(.trailing, 60)
                .padding(.top, 20)

                if case .eventCountdown(let title, let start, let meetingURL) = eventCountdown {
                    EventCountdown.Row(title: title, start: start, meetingURL: meetingURL, coordinator: coordinator)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                }

                SeekerBar(media: media)
                    .padding(.horizontal, 28)
                    .padding(.top, 18)

                ZStack {
                    HStack(spacing: 44) {
                        ControlButton(symbol: "backward.fill", size: 20) { media.send(.previousTrack) }
                        ControlButton(symbol: media.nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                                      size: 26) { media.send(.togglePlayPause) }
                        ControlButton(symbol: "forward.fill", size: 20) { media.send(.nextTrack) }
                    }
                    HStack {
                        if coordinator.playerBridge.isAvailable {
                            PlayerControlsRow(bridge: coordinator.playerBridge)
                                .padding(.leading, 18)
                        }
                        Spacer()
                        OutputPicker(outputs: coordinator.outputs).padding(.trailing, 18)
                    }
                }
                .frame(height: 44)
                .padding(.top, 6)
            }
            Button {
                NotchActions.popMenu([
                    ("Mostrar no app", { NotchActions.openPlayer() }),
                    ("Ajustes…", { SettingsWindowManager.shared.show(coordinator: coordinator) }),
                ])
            } label: {
                Text("······")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(NotchButtonStyle())
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 22)
            .padding(.top, max(30, notchTop - 6))
        }
        .onChange(of: media.nowPlaying.title) { _, _ in fetchLyricsIfNeeded() }
        .onChange(of: media.nowPlaying.artist) { _, _ in fetchLyricsIfNeeded() }
        .onChange(of: coordinator.config.lyricsEnabled) { _, _ in fetchLyricsIfNeeded() }
        .onAppear { fetchLyricsIfNeeded() }
    }

    private func fetchLyricsIfNeeded() {
        guard coordinator.config.lyricsEnabled else { return }
        coordinator.lyrics.fetch(
            title: media.nowPlaying.title,
            artist: media.nowPlaying.artist,
            album: media.nowPlaying.album,
            duration: media.nowPlaying.duration)
    }
}

struct FloatingHUDPill: View {
    let activity: NotchActivity

    var body: some View {
        let row = ExpandedHUDRow(activity: activity)
            .padding(.horizontal, 14)
            .frame(width: 250, height: 36)
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            GlassEffectContainer {
                row.glassEffect(.regular.tint(.black.opacity(0.25)), in: Capsule(style: .continuous))
            }
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        } else {
            Self.fallback(row)
        }
        #else
        Self.fallback(row)
        #endif
    }

    @ViewBuilder
    private static func fallback(_ row: some View) -> some View {
        row
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

struct ExpandedHUDRow: View {
    let activity: NotchActivity

    private var level: Float {
        switch activity {
        case .volume(let v, let m): m ? 0 : v
        case .brightness(let v), .keyboardBrightness(let v): v
        default: 0
        }
    }
    private var symbol: String {
        switch activity {
        case .volume(_, let m): m ? "speaker.slash.fill" : (level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
        case .brightness: "sun.max.fill"
        case .keyboardBrightness: "keyboard"
        default: "circle"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            LevelBar(level: level, tint: .white, width: nil)
                .frame(height: 6)
            Text("\(Int((level * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 38, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }
}

private struct OutputPicker: View {
    @ObservedObject var outputs: OutputDevices

    var body: some View {
        Button {
            NotchActions.popMenu(outputs.devices.map { d in
                ((d == outputs.current ? "✓ " : "   ") + d.name, { outputs.select(d) })
            })
        } label: {
            Image(systemName: outputs.current?.symbol ?? "laptopcomputer")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle())
        .help(outputs.current?.name ?? "Saída de áudio")
    }
}

private struct PinnedAppsRow: View {
    let bundleIDs: [String]
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: 6) {
            ForEach(bundleIDs, id: \.self) { id in
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Button {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    } label: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: size, height: size)
                            .padding(4)
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(NotchButtonStyle())
                    .help(url.deletingPathExtension().lastPathComponent)
                }
            }
        }
    }
}

struct CalendarWidget: View {
    @ObservedObject var calendar: CalendarService
    var firstWeekday: Int = Calendar.current.firstWeekday
    var coordinator: NotchCoordinator?
    @State private var editing: CalendarService.UpcomingEvent?
    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = firstWeekday; return c }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date(), format: .dateTime.month(.wide).year())
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.red).textCase(.uppercase)
                let days = monthDays()
                let labels = CalendarGrid.weekdayLabels(firstWeekday: firstWeekday)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(16), spacing: 3), count: 7), spacing: 2) {
                    ForEach(labels.indices, id: \.self) { i in
                        Text(labels[i]).font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    ForEach(days.indices, id: \.self) { i in
                        let d = days[i]
                        Text(d.map { "\($0)" } ?? "")
                            .font(.system(size: 9, weight: d == today ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(d == today ? .black : .white.opacity(0.85))
                            .frame(width: 16, height: 14)
                            .background(Circle().fill(d == today ? Color.white : .clear))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Próximos").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                if calendar.upcoming.isEmpty {
                    Text("Nada nas próximas 24h").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                ForEach(calendar.upcoming.prefix(4), id: \.start) { e in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5).fill(.purple).frame(width: 3, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(e.start, format: .dateTime.hour().minute())
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = e }
                    .popover(item: Binding(
                        get: { editing?.id == e.id ? editing : nil },
                        set: { editing = $0 }
                    )) { event in
                        EditEventPopover(calendar: calendar, event: event, coordinator: coordinator) { editing = nil }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onTapGesture { NotchActions.openCalendar() }
    }

    private var today: Int { cal.component(.day, from: Date()) }

    private func monthDays() -> [Int?] {
        let now = Date()
        guard let range = cal.range(of: .day, in: .month, for: now),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return [] }
        let weekdayOfFirst = cal.component(.weekday, from: first)
        let lead = CalendarGrid.leadingBlanks(firstWeekdayOfMonth: weekdayOfFirst, firstWeekday: firstWeekday)
        return Array(repeating: nil, count: lead) + range.map { Optional($0) }
    }
}

private struct EditEventPopover: View {
    @ObservedObject var calendar: CalendarService
    let event: CalendarService.UpcomingEvent
    var coordinator: NotchCoordinator?
    let onDone: () -> Void
    @State private var title: String
    @State private var start: Date
    @State private var end: Date

    init(calendar: CalendarService, event: CalendarService.UpcomingEvent, coordinator: NotchCoordinator? = nil, onDone: @escaping () -> Void) {
        self.calendar = calendar
        self.event = event
        self.coordinator = coordinator
        self.onDone = onDone
        _title = State(initialValue: event.title)
        _start = State(initialValue: event.start)
        _end = State(initialValue: event.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Título", text: $title).textFieldStyle(.roundedBorder)
            DatePicker("Início", selection: $start).datePickerStyle(.compact)
            DatePicker("Fim", selection: $end).datePickerStyle(.compact)
            HStack {
                Button("Excluir", role: .destructive) {
                    guard let id = event.eventID else { onDone(); return }
                    do {
                        try calendar.delete(eventID: id)
                        onDone()
                    } catch {
                        coordinator?.notify(app: "Calendário", title: "Não foi possível salvar/excluir")
                    }
                }
                Spacer()
                Button("Salvar") {
                    guard let id = event.eventID else { onDone(); return }
                    do {
                        try calendar.update(eventID: id, title: title, start: start, end: end)
                        onDone()
                    } catch {
                        coordinator?.notify(app: "Calendário", title: "Não foi possível salvar/excluir")
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear { NotchPanelController.current?.makeKey() }
        .onDisappear { NotchPanelController.current?.resignKey() }
    }
}

struct NotificationsWidget: View {
    let bundleID: String
    @ObservedObject var mirror: NotificationMirror

    var body: some View {
        let notes = mirror.notes(for: bundleID)
        VStack(alignment: .leading, spacing: 6) {
            if !mirror.available {
                Label("Ative Acesso Total ao Disco pro Cove ver as notificações deste app.",
                      systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Button("Abrir Privacidade…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                .controlSize(.small)
            } else if notes.isEmpty {
                Text("Sem notificações recentes").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            } else {
                ForEach(notes.prefix(4)) { n in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(n.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Text(n.date, format: .dateTime.hour().minute())
                                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                        }
                        if !n.body.isEmpty {
                            Text(n.body).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                        }
                    }
                    .padding(.vertical, 3).padding(.horizontal, 8)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .onTapGesture {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        }
    }
}

private struct CalendarColumn: View {
    @ObservedObject var calendar: CalendarService
    let enabled: Bool

    var body: some View {
        if enabled {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(), format: .dateTime.weekday(.abbreviated))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.red)
                    .textCase(.uppercase)
                Text(Date(), format: .dateTime.day())
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                if let e = calendar.next {
                    HStack(spacing: 4) {
                        Circle().fill(.purple).frame(width: 6, height: 6)
                        Text(e.title).lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.purple.opacity(0.28), in: Capsule())
                } else {
                    Text("Sem eventos")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: 120, alignment: .leading)
        }
    }
}

private struct InfoChipsRow: View {
    @ObservedObject var coordinator: NotchCoordinator
    @ObservedObject var weather: WeatherService
    @ObservedObject var calendar: CalendarService

    init(coordinator: NotchCoordinator) {
        self.coordinator = coordinator
        self.weather = coordinator.weather
        self.calendar = coordinator.calendar
    }

    var body: some View {
        HStack(spacing: 14) {
            if coordinator.config.showWeather, calendar.next == nil, let w = weather.current {
                Label("\(Int(w.tempC.rounded()))°", systemImage: w.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
            }
            if coordinator.config.showCalendar, let e = calendar.next {
                Label {
                    Text("\(e.title) · \(e.start, format: .dateTime.hour().minute())")
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(e.isSoon ? .red.opacity(0.9) : .white.opacity(0.7))
            }
        }
        .frame(maxWidth: 400)
    }
}

private struct SeekerBar: View {
    @ObservedObject var media: MediaRemoteService
    @GestureState private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let np = media.nowPlaying
            let elapsed = dragFraction.map { $0 * np.duration } ?? (np.isPlaying
                ? min(np.elapsed + context.date.timeIntervalSince(media.lastElapsedUpdate), np.duration)
                : np.elapsed)
            HStack(spacing: 8) {
                Text(Self.fmt(elapsed))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white.opacity(dragFraction != nil ? 1 : 0.85))
                            .frame(width: np.duration > 0
                                ? geo.size.width * CGFloat(elapsed / np.duration) : 0)
                    }
                    .contentShape(Rectangle().inset(by: -8))
                    .gesture(DragGesture(minimumDistance: 0)
                        .updating($dragFraction) { v, state, _ in
                            state = min(max(v.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { v in
                            let f = min(max(v.location.x / geo.size.width, 0), 1)
                            media.seek(to: f * np.duration)
                        })
                }
                .frame(height: 5)
                Text("-" + Self.fmt(max(np.duration - elapsed, 0)))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    static func fmt(_ t: Double) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct NotchHover: ViewModifier {
    @State private var over = false

    func body(content: Content) -> some View {
        content
            .background(Circle().fill(.white.opacity(over ? 0.13 : 0)))
            .animation(.smooth(duration: 0.16), value: over)
            .onHover { o in
                guard o != over else { return }
                over = o
                if o { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            }
    }
}

struct NotchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(duration: 0.14, bounce: 0.25), value: configuration.isPressed)
            .modifier(NotchHover())
    }
}

extension View {
    func notchHover() -> some View { modifier(NotchHover()) }
}

private struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 16
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle())
    }
}

private struct PlayerControlsRow: View {
    @ObservedObject var bridge: PlayerBridge

    var body: some View {
        HStack(spacing: 10) {
            let shuffle = PlayerState.symbol(for: .shuffle(bridge.state.shuffle))
            MediaToggleButton(symbol: shuffle.name, tinted: shuffle.tinted, help: "Aleatório") {
                bridge.toggleShuffle()
            }
            let repeatSymbol = PlayerState.symbol(for: .repeatMode(bridge.state.repeatMode))
            MediaToggleButton(symbol: repeatSymbol.name, tinted: repeatSymbol.tinted, help: "Repetir") {
                bridge.cycleRepeat()
            }
            if bridge.state.supportsFavorite {
                let favorite = PlayerState.symbol(for: .favorite(bridge.state.favorite))
                MediaToggleButton(symbol: favorite.name, tinted: favorite.tinted, help: "Favoritar") {
                    bridge.toggleFavorite()
                }
            }
        }
    }
}

private struct MediaToggleButton: View {
    let symbol: String
    let tinted: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tinted ? .white : .white.opacity(0.5))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle())
        .help(help)
    }
}

private struct HUDStyleKey: EnvironmentKey { static let defaultValue = "white" }
extension EnvironmentValues {
    var hudStyle: String {
        get { self[HUDStyleKey.self] }
        set { self[HUDStyleKey.self] = newValue }
    }
}

enum NotchActions {
    @MainActor static func popMenu(_ items: [(String, () -> Void)]) {
        let menu = NSMenu()
        for (title, action) in items {
            let item = NSMenuItem(title: title, action: #selector(MenuTarget.fire(_:)), keyEquivalent: "")
            let target = MenuTarget(action)
            item.target = target
            item.representedObject = target
            menu.addItem(item)
        }
        NotchPanelController.current?.pushLoweredLevel()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        NotchPanelController.current?.popLoweredLevel()
    }

    static func openCalendar() {
        if let url = URL(string: "ical://") { NSWorkspace.shared.open(url) }
    }
    static func openPlayer() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

final class MenuTarget: NSObject {
    let action: () -> Void
    init(_ a: @escaping () -> Void) { action = a }
    @objc func fire(_ sender: Any?) { action() }
}

private struct MarqueeText: View {
    let text: String
    let font: Font
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var loopTask: Task<Void, Never>?

    private var overflow: CGFloat { max(textWidth - boxWidth, 0) }

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .fixedSize()
                .background(GeometryReader { t in
                    Color.clear
                        .onAppear { textWidth = t.size.width }
                        .onChange(of: t.size.width) { textWidth = t.size.width }
                })
                .offset(x: -offset)
                .onAppear { boxWidth = geo.size.width }
                .onChange(of: geo.size.width) { boxWidth = geo.size.width }
        }
        .clipped()
        .mask {
            if overflow > 0 {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                       .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            } else {
                Color.black
            }
        }
        .onChange(of: overflow, initial: true) { restart() }
        .onDisappear { loopTask?.cancel() }
    }

    private func restart() {
        loopTask?.cancel()
        offset = 0
        guard overflow > 0 else { return }
        let d = Double(overflow) / 28
        let target = overflow
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: d)) { offset = target }
                try? await Task.sleep(for: .seconds(d + 1.2))
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: d)) { offset = 0 }
                try? await Task.sleep(for: .seconds(d))
            }
        }
    }
}

private struct ArtworkThumb: View {
    @ObservedObject var media: MediaRemoteService
    let size: CGFloat
    @State private var flip = 0.0

    var body: some View {
        if let art = media.nowPlaying.artwork {
            Image(nsImage: art)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.5))
                .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0))
                .onChange(of: media.nowPlaying.title) {
                    withAnimation(.spring(duration: 0.55, bounce: 0.15)) { flip += 360 }
                }
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.white.opacity(0.12))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.white.opacity(0.5))
                }
        }
    }
}

private struct PageBar: View {
    let pages: [Droplet]
    let current: Int
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { i in
                Image(systemName: pages[i].symbol)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(i == current ? 0.95 : 0.35))
                    .frame(width: 14, height: 12)
                    .background(
                        Capsule().fill(.white.opacity(i == current ? 0.18 : 0)))
                    .contentShape(Rectangle())
                    .onTapGesture { select(i) }
                    .help(pages[i].title)
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Capsule().fill(.white.opacity(0.06)))
        .animation(.spring(duration: 0.25, bounce: 0.15), value: current)
    }
}
