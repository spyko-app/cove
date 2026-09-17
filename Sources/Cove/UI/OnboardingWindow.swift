import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowManager {
    static let shared = OnboardingWindowManager()
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func showIfNeeded(coordinator: NotchCoordinator) {
        guard !coordinator.config.onboardingDone,
              AppEnvironment.isBundledApp,
              ProcessInfo.processInfo.environment["COVE_PREVIEW_HUD"] == nil,
              ProcessInfo.processInfo.environment["COVE_PREVIEW_NOMEDIA"] == nil else { return }
        show(coordinator: coordinator)
    }

    func show(coordinator: NotchCoordinator) {
        if let window { window.makeKeyAndOrderFront(nil); window.orderFrontRegardless(); NSApplication.shared.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentViewController: NSHostingController(
            rootView: OnboardingTourView(coordinator: coordinator) { [weak self] in
                self?.window?.close()
                self?.window = nil
            }))
        w.title = "Bem-vindo ao Cove"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.setContentSize(NSSize(width: 520, height: 560))
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window = w
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main
        ) { _ in
            Task { @MainActor in coordinator.requestExpand(false) }
        }
    }
}

private struct OnboardingTourView: View {
    @ObservedObject var coordinator: NotchCoordinator
    let done: () -> Void

    @State private var page = 0
    @StateObject private var permissionState = PermissionState()

    private let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: TourWelcomePage()
                case 1: TourMediaPage(coordinator: coordinator)
                case 2: TourGesturesPage()
                case 3: TourDropletsPage(coordinator: coordinator)
                default: TourPermissionsPage(coordinator: coordinator, state: permissionState)
                }
            }
            .id(page)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 12)

            HStack {
                if page < pageCount - 1 {
                    Button("Pular") { finish() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                } else {
                    Spacer().frame(width: 44)
                }

                Spacer()

                if page > 0 {
                    Button("Voltar") { withAnimation { page = TourPages.prev(page, count: pageCount) } }
                }
                if page < pageCount - 1 {
                    Button("Continuar") { withAnimation { page = TourPages.next(page, count: pageCount) } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Começar") { finish() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding([.horizontal, .bottom], 20)
        }
    }

    private func finish() {
        coordinator.requestExpand(false)
        coordinator.updateConfig { $0.onboardingDone = true }
        done()
    }
}
