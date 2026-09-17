import Foundation

/// Timer/Pomodoro da ilha: sessão única com contagem regressiva.
@MainActor
final class TimerService: ObservableObject {
    struct Session: Equatable { var label: String; var total: Int; var remaining: Int; var isRunning: Bool }
    static let pomodoroWork = 25 * 60, pomodoroBreak = 5 * 60

    @Published private(set) var session: Session?
    var onFinished: ((String) -> Void)?
    private var endDate: Date?
    private var timer: Timer?

    init(autoTick: Bool = true) {
        guard autoTick else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(now: Date()) }
        }
    }

    func start(label: String, seconds: Int, now: Date = Date()) {
        session = Session(label: label, total: seconds, remaining: seconds, isRunning: true)
        endDate = now.addingTimeInterval(TimeInterval(seconds))
    }
    func pause() { session?.isRunning = false; endDate = nil }
    func resume(now: Date = Date()) {
        guard let s = session else { return }
        session?.isRunning = true
        endDate = now.addingTimeInterval(TimeInterval(s.remaining))
    }
    func stop() { session = nil; endDate = nil }

    /// Estende a sessão em `seconds` (ação "+5 min" da atividade expandida):
    /// soma no total E no restante; se estiver rodando, empurra o `endDate`.
    func extend(by seconds: Int, now: Date = Date()) {
        guard var s = session, seconds > 0 else { return }
        s.total += seconds
        s.remaining += seconds
        session = s
        if s.isRunning { endDate = now.addingTimeInterval(TimeInterval(s.remaining)) }
    }

    func tick(now: Date) {
        guard var s = session, s.isRunning, let end = endDate else { return }
        let left = Int(end.timeIntervalSince(now).rounded(.up))
        if left <= 0 {
            let label = s.label
            session = nil; endDate = nil
            onFinished?(label)
        } else if left != s.remaining {
            s.remaining = left; session = s
        }
    }
}
