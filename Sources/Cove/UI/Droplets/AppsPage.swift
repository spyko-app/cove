import AppKit
import SwiftUI

struct AppsPage: View {
    @ObservedObject var coordinator: NotchCoordinator
    let notchTop: CGFloat
    @State private var selected: String?

    private var apps: [String] {
        coordinator.config.pinnedApps.isEmpty ? ["com.apple.iCal"] : coordinator.config.pinnedApps
    }

    private var eventCountdown: NotchActivity? {
        if case .eventCountdown = coordinator.ambientActivity { return coordinator.ambientActivity }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchTop)
            if case .eventCountdown(let title, let start, let meetingURL) = eventCountdown {
                EventCountdown.Row(title: title, start: start, meetingURL: meetingURL, coordinator: coordinator)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    ForEach(apps, id: \.self) { id in
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 28, height: 28)
                                .padding(3)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.white.opacity((selected ?? apps.first) == id ? 0.16 : 0)))
                                .animation(.smooth(duration: 0.16), value: selected)
                                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .onHover { over in
                                    guard over, selected != id else { return }
                                    selected = id
                                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                }
                                .onTapGesture(count: 2) {
                                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                                }
                        }
                    }
                }
                .frame(width: 44)
                Group {
                    let cur = selected ?? apps.first ?? ""
                    if cur == "com.apple.iCal" {
                        CalendarWidget(calendar: coordinator.calendar, firstWeekday: coordinator.config.firstWeekday, coordinator: coordinator)
                    } else {
                        NotificationsWidget(bundleID: cur, mirror: coordinator.notifications)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.blurReplace)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .onAppear { coordinator.notifications.recheck() }
    }
}
