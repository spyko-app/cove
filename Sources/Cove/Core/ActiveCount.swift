import Foundation

@MainActor
final class ActiveCount {
    private(set) var count = 0
    private let onFirst: () -> Void
    private let onLast: () -> Void

    init(onFirst: @escaping () -> Void, onLast: @escaping () -> Void) {
        self.onFirst = onFirst
        self.onLast = onLast
    }

    func retain() {
        count = Self.nextCount(count, retain: true)
        if count == 1 { onFirst() }
    }

    func release() {
        let previous = count
        count = Self.nextCount(count, retain: false)
        if previous == 1, count == 0 { onLast() }
    }

    nonisolated static func nextCount(_ current: Int, retain: Bool) -> Int {
        retain ? current + 1 : max(0, current - 1)
    }
}
