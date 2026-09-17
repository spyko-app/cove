import XCTest
@testable import Cove

final class ActivityQueueTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Ordem FIFO

    func testFIFOOrder() {
        var q = ActivityQueue()
        q.enqueue(.notification(app: "A", title: "1"), duration: 4, now: base)
        q.enqueue(.event(title: "B", minutes: 1), duration: 4, now: base)
        let first = q.next(now: base)
        let second = q.next(now: base)
        XCTAssertEqual(first?.activity, .notification(app: "A", title: "1"))
        XCTAssertEqual(second?.activity, .event(title: "B", minutes: 1))
        XCTAssertTrue(q.isEmpty)
    }

    // MARK: - Coalescing por tipo

    func testCoalescingKeepsPositionAndReplacesPayload() {
        var q = ActivityQueue()
        q.enqueue(.notification(app: "A", title: "primeira"), duration: 4, now: base)
        q.enqueue(.event(title: "meio", minutes: 1), duration: 4, now: base)
        // segunda notificação chega depois — mesmo tipo, deve substituir a
        // primeira MANTENDO a posição (na frente do evento), não ir pro fim.
        q.enqueue(.notification(app: "A", title: "segunda"), duration: 4, now: base)
        let first = q.next(now: base)
        let second = q.next(now: base)
        XCTAssertEqual(first?.activity, .notification(app: "A", title: "segunda"))
        XCTAssertEqual(second?.activity, .event(title: "meio", minutes: 1))
    }

    // MARK: - removeAll(kindKey:) — notificação enfileirada no instante do lock

    func testRemoveAllKindKeyDropsOnlyThatKind() {
        var q = ActivityQueue()
        q.enqueue(.notification(app: "A", title: "1"), duration: 4, now: base)
        q.enqueue(.event(title: "B", minutes: 1), duration: 4, now: base)
        q.removeAll(kindKey: "notification")
        XCTAssertEqual(q.next(now: base)?.activity, .event(title: "B", minutes: 1))
        XCTAssertTrue(q.isEmpty)
    }

    func testRemoveAllKindKeyOnEmptyQueueIsNoop() {
        var q = ActivityQueue()
        q.removeAll(kindKey: "notification")
        XCTAssertTrue(q.isEmpty)
    }

    // MARK: - Expiração

    func testExpiredEntryIsDropped() {
        var q = ActivityQueue()
        q.enqueue(.notification(app: "A", title: "velha"), duration: 4, now: base)
        // esperou mais que duration*2 (8s) → descarta ao tentar tirar da fila
        let later = base.addingTimeInterval(9)
        XCTAssertNil(q.next(now: later))
        XCTAssertTrue(q.isEmpty)
    }

    func testNonExpiredEntrySurvives() {
        var q = ActivityQueue()
        q.enqueue(.notification(app: "A", title: "ok"), duration: 4, now: base)
        let later = base.addingTimeInterval(7)
        XCTAssertNotNil(q.next(now: later))
    }

    func testExpiredEntrySkippedButLaterOneReturned() {
        var q = ActivityQueue()
        q.enqueue(.notification(app: "A", title: "velha"), duration: 4, now: base)
        q.enqueue(.event(title: "nova", minutes: 1), duration: 4, now: base.addingTimeInterval(9))
        let result = q.next(now: base.addingTimeInterval(9))
        XCTAssertEqual(result?.activity, .event(title: "nova", minutes: 1))
    }

    // MARK: - Matriz de decisão

    func testHUDOverEventShowsNow() {
        let q = ActivityQueue()
        let decision = q.decision(for: .volume(0.5, muted: false), current: .notification(app: "A", title: "x"))
        XCTAssertEqual(decision, .showNow)
    }

    func testEventOverEventEnqueues() {
        let q = ActivityQueue()
        let decision = q.decision(for: .notification(app: "B", title: "y"), current: .notification(app: "A", title: "x"))
        XCTAssertEqual(decision, .enqueue)
    }

    func testEventOverHUDShowsNow() {
        let q = ActivityQueue()
        let decision = q.decision(for: .notification(app: "A", title: "x"), current: .volume(0.5, muted: false))
        XCTAssertEqual(decision, .showNow)
    }

    func testSameEventEqualShowsNow() {
        let q = ActivityQueue()
        let decision = q.decision(
            for: .notification(app: "A", title: "x"),
            current: .notification(app: "A", title: "x")
        )
        XCTAssertEqual(decision, .showNow)
    }

    func testEventOverNilShowsNow() {
        let q = ActivityQueue()
        let decision = q.decision(for: .notification(app: "A", title: "x"), current: nil)
        XCTAssertEqual(decision, .showNow)
    }

    func testHUDOverHUDShowsNow() {
        let q = ActivityQueue()
        let decision = q.decision(for: .brightness(0.5), current: .volume(0.5, muted: false))
        XCTAssertEqual(decision, .showNow)
    }
}
