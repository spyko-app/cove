import EventKit
import Foundation

/// Próximo evento do calendário (EventKit) — chip no expandido + peek
/// "time to leave" minutos antes do evento.
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
    @Published var upcoming: [UpcomingEvent] = []   // próximas 24h (widget)
    /// IDs dos calendários selecionados em Ajustes › Calendário. Vazio = todos.
    @Published var selectedCalendarIDs: [String] = [] {
        didSet { refresh() }
    }
    var onTimeToLeave: ((UpcomingEvent) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var warned: Set<Date> = []

    init() {
        // Sem pedido de acesso aqui — TCC só no primeiro uso real (tour, ou
        // ao expandir a ilha com o widget de calendário ligado). Se o acesso
        // já foi concedido numa sessão anterior, aproveita e começa a atualizar.
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

    /// Pede acesso ao Calendário na hora (tour, ou primeira expansão da ilha
    /// com o widget ligado) — nunca no boot. Idempotente: não repete o prompt
    /// se já decidido.
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

    /// Cria evento a partir de um `NaturalEvent.Draft` — pede acesso na hora
    /// (Droppy #15/#17: API real só no primeiro uso, nunca no boot).
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

    /// Cria lembrete (sem hora fixa de término) a partir de um `NaturalEvent.Draft`
    /// com `kind == .reminder` — pede acesso a Lembretes na hora, nunca no boot.
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

    /// Calendários de evento disponíveis (id, título, cor) — pra lista de toggles em Ajustes.
    func calendars() -> [(id: String, title: String, color: CGColor)] {
        store.calendars(for: .event).map { ($0.calendarIdentifier, $0.title, $0.cgColor) }
    }

    /// Atualiza um evento existente (título/início/fim) — usado pelo popover de edição.
    func update(eventID: String, title: String, start: Date, end: Date) throws {
        guard let ev = store.event(withIdentifier: eventID) else { return }
        ev.title = title
        ev.startDate = start
        ev.endDate = end
        try store.save(ev, span: .thisEvent)
        refresh()
    }

    /// Exclui um evento existente — usado pelo popover de edição.
    func delete(eventID: String) throws {
        guard let ev = store.event(withIdentifier: eventID) else { return }
        try store.remove(ev, span: .thisEvent)
        refresh()
    }

    /// Filtro puro de eventos por calendário selecionado — testável sem EventKit.
    /// `selectedIDs` vazio = sem filtro (todos os calendários).
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
        // aviso único aos 10 min
        if up.start.timeIntervalSinceNow < 10 * 60, !warned.contains(up.start) {
            warned.insert(up.start)
            onTimeToLeave?(up)
        }
    }
}

/// Qualquer coisa filtrável por calendário — permite testar `CalendarService.filter`
/// com uma struct pura, sem depender de EventKit.
protocol CalendarIdentifiable {
    var calendarID: String { get }
}
