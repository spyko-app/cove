import EventKit
import Foundation

@MainActor
final class CalendarService: ObservableObject {
    struct UpcomingEvent: Equatable, Identifiable {
        var eventID: String?
        var title: String
        var start: Date
        var end: Date = Date()
        var meetingURL: URL?
        var id: String { eventID ?? "\(title)-\(start.timeIntervalSinceReferenceDate)" }
        var isSoon: Bool { start.timeIntervalSinceNow < 15 * 60 }
    }

    @Published var next: UpcomingEvent?
    @Published var upcoming: [UpcomingEvent] = []
    @Published var selectedCalendarIDs: [String] = [] {
        didSet { refresh() }
    }
    var onTimeToLeave: ((UpcomingEvent) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var warned: Set<Date> = []

    init() {
        guard AppEnvironment.isBundledApp else { return }
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            refresh()
            startTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    @discardableResult
    func requestAccessIfNeeded() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            refresh()
            startTimer()
            return true
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            if granted {
                refresh()
                startTimer()
            }
            return granted
        default:
            return false
        }
    }

    enum CreateError: Error { case accessDenied }

    func create(_ d: NaturalEvent.Draft) async throws {
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else { throw CreateError.accessDenied }
        }
        let ev = EKEvent(eventStore: store)
        ev.title = d.title
        ev.startDate = d.start
        ev.endDate = d.end
        ev.calendar = store.defaultCalendarForNewEvents
        try store.save(ev, span: .thisEvent)
        refresh()
    }

    func createReminder(_ d: NaturalEvent.Draft) async throws {
        if EKEventStore.authorizationStatus(for: .reminder) != .fullAccess {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else { throw CreateError.accessDenied }
        }
        let r = EKReminder(eventStore: store)
        r.title = d.title
        r.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: d.start)
        r.calendar = store.defaultCalendarForNewReminders()
        try store.save(r, commit: true)
    }

    func calendars() -> [(id: String, title: String, color: CGColor)] {
        store.calendars(for: .event).map { ($0.calendarIdentifier, $0.title, $0.cgColor) }
    }

    func update(eventID: String, title: String, start: Date, end: Date) throws {
        guard let ev = store.event(withIdentifier: eventID) else { return }
        ev.title = title
        ev.startDate = start
        ev.endDate = end
        try store.save(ev, span: .thisEvent)
        refresh()
    }

    func delete(eventID: String) throws {
        guard let ev = store.event(withIdentifier: eventID) else { return }
        try store.remove(ev, span: .thisEvent)
        refresh()
    }

    nonisolated static func filter<E: CalendarIdentifiable>(events: [E], selectedIDs: [String]) -> [E] {
        guard !selectedIDs.isEmpty else { return events }
        return events.filter { selectedIDs.contains($0.calendarID) }
    }

    private func refresh() {
        let now = Date()
        let calendars: [EKCalendar]? = selectedCalendarIDs.isEmpty
            ? nil
            : store.calendars(for: .event).filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(
            withStart: now, end: now.addingTimeInterval(24 * 3600), calendars: calendars)
        let all = store.events(matching: predicate)
            .filter { $0.startDate > now || $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        upcoming = all.prefix(5).map {
            UpcomingEvent(eventID: $0.eventIdentifier, title: $0.title ?? "Evento", start: $0.startDate, end: $0.endDate)
        }
        let events = all.filter { !$0.isAllDay && $0.startDate > now && $0.startDate.timeIntervalSince(now) < 12 * 3600 }
        guard let e = events.first else { next = nil; return }
        let meetingURL = MeetingLink.extract(from: e.notes, url: e.url, location: e.location)
        let up = UpcomingEvent(eventID: e.eventIdentifier, title: e.title ?? "Evento", start: e.startDate, end: e.endDate, meetingURL: meetingURL)
        next = up
        if up.start.timeIntervalSinceNow < 10 * 60, !warned.contains(up.start) {
            warned.insert(up.start)
            onTimeToLeave?(up)
        }
    }
}

protocol CalendarIdentifiable {
    var calendarID: String { get }
}
