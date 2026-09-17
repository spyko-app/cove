import XCTest
@testable import Cove

final class MeetingLinkTests: XCTestCase {
    func testExtractsEachKnownHost() {
        let hosts = [
            "https://zoom.us/j/123456",
            "https://meet.google.com/abc-defg-hij",
            "https://teams.microsoft.com/l/meetup-join/xyz",
            "https://facetime.apple.com/join#v=1&p=abc",
            "https://webex.com/meet/room1",
            "https://whereby.com/my-room",
        ]
        for host in hosts {
            let notes = "Entra aqui: \(host) — não esquece."
            let found = MeetingLink.extract(from: notes, url: nil, location: nil)
            XCTAssertEqual(found?.absoluteString, host, "falhou pro host \(host)")
        }
    }

    func testNoLinkReturnsNil() {
        let found = MeetingLink.extract(from: "Reunião presencial na sala 3", url: nil, location: "Sala 3")
        XCTAssertNil(found)
    }

    func testTwoLinksInNotesFirstMeetingWins() {
        let notes = "Ref: https://example.com/doc depois https://zoom.us/j/999 e https://meet.google.com/xyz-abcd"
        let found = MeetingLink.extract(from: notes, url: nil, location: nil)
        XCTAssertEqual(found?.absoluteString, "https://zoom.us/j/999")
    }

    func testPlainURLFallback() {
        let url = URL(string: "https://minha-empresa.com/sala-de-reuniao")!
        let found = MeetingLink.extract(from: nil, url: url, location: nil)
        XCTAssertEqual(found, url)
    }

    func testLocationChecked() {
        let found = MeetingLink.extract(from: nil, url: nil, location: "Entrar via https://teams.microsoft.com/l/meetup-join/abc")
        XCTAssertEqual(found?.host, "teams.microsoft.com")
    }
}
