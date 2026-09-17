import XCTest
@testable import Cove

final class NaturalEventTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)

    func testParsesTitleAndTime() throws {
        let now = Date()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let d = try XCTUnwrap(NaturalEvent.parse("Reunião com Alef amanhã às 15h", now: now, calendar: cal))
        XCTAssertEqual(d.title, "Reunião com Alef")
        XCTAssertEqual(cal.component(.day, from: d.start), cal.component(.day, from: tomorrow))
        XCTAssertEqual(cal.component(.hour, from: d.start), 15)
        XCTAssertEqual(d.end.timeIntervalSince(d.start), 3600)
    }

    func testNoDateReturnsNil() {
        XCTAssertNil(NaturalEvent.parse("só um texto", now: Date(), calendar: cal))
    }

    func testReminderPrefixDetected() throws {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 9; c.hour = 10
        let now = cal.date(from: c)!
        let d = try XCTUnwrap(NaturalEvent.parse("lembrar de pagar conta amanhã às 15h", now: now, calendar: cal))
        XCTAssertEqual(d.kind, .reminder)
        XCTAssertEqual(d.title, "pagar conta")
    }

    func testReminderMeLembraPrefixDetected() throws {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 9; c.hour = 10
        let now = cal.date(from: c)!
        let d = try XCTUnwrap(NaturalEvent.parse("me lembra de ligar pro dentista amanhã às 9h", now: now, calendar: cal))
        XCTAssertEqual(d.kind, .reminder)
        XCTAssertEqual(d.title, "ligar pro dentista")
    }

    func testEventWithoutPrefixStaysEvent() throws {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 9; c.hour = 10
        let now = cal.date(from: c)!
        let d = try XCTUnwrap(NaturalEvent.parse("Reunião com Alef amanhã às 15h", now: now, calendar: cal))
        XCTAssertEqual(d.kind, .event)
    }
}
