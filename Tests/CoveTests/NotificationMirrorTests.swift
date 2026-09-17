import XCTest
@testable import Cove

final class NotificationMirrorTests: XCTestCase {
    private func note(_ id: Int, app: String, bundleID: String, title: String, body: String) -> NotificationMirror.Note {
        NotificationMirror.Note(id: id, app: app, bundleID: bundleID, title: title, body: body, date: Date())
    }

    func testGroupingAndSearch() {
        let notes = [
            note(3, app: "WhatsApp", bundleID: "net.whatsapp.WhatsApp", title: "Mateus", body: "Oi tudo bem?"),
            note(2, app: "Mail", bundleID: "com.apple.mail", title: "Fatura", body: "Vencimento amanhã"),
            note(1, app: "WhatsApp", bundleID: "net.whatsapp.WhatsApp", title: "Grupo Cove", body: "Reunião às 10h"),
        ]

        let all = NotificationMirror.group(notes, query: "")
        XCTAssertEqual(all.map(\.bundleID), ["net.whatsapp.WhatsApp", "com.apple.mail"])
        XCTAssertEqual(all[0].notes.map(\.id), [3, 1])
        XCTAssertEqual(all[1].notes.map(\.id), [2])

        let byTitle = NotificationMirror.group(notes, query: "grupo")
        XCTAssertEqual(byTitle.map(\.bundleID), ["net.whatsapp.WhatsApp"])
        XCTAssertEqual(byTitle[0].notes.map(\.id), [1])

        let byBodyCaseInsensitive = NotificationMirror.group(notes, query: "VENCIMENTO")
        XCTAssertEqual(byBodyCaseInsensitive.map(\.bundleID), ["com.apple.mail"])

        let byApp = NotificationMirror.group(notes, query: "whatsapp")
        XCTAssertEqual(byApp.map(\.bundleID), ["net.whatsapp.WhatsApp"])
        XCTAssertEqual(byApp[0].notes.count, 2)

        XCTAssertTrue(NotificationMirror.group(notes, query: "nada aqui").isEmpty)
    }

    private func row(rec: Int, bundleID: String, title: String, body: String) -> String {
        let plist: [String: Any] = ["req": ["titl": title, "body": body]]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let hex = data.map { String(format: "%02X", $0) }.joined()
        return "\(rec)\u{1F}X'\(hex)'\u{1F}\(bundleID)\u{1F}0"
    }

    @MainActor
    func testIngestDoesNotResurrectAfterClear() {
        let mirror = NotificationMirror()
        let bundleID = "net.whatsapp.WhatsApp"
        let firstRow = row(rec: 1, bundleID: bundleID, title: "Mateus", body: "Oi")

        mirror.ingest(rows: [firstRow], emit: false)
        XCTAssertEqual(mirror.recent.map(\.id), [1])

        mirror.clear(bundleID: bundleID)
        XCTAssertTrue(mirror.recent.isEmpty)

        mirror.ingest(rows: [firstRow], emit: false)
        XCTAssertTrue(mirror.recent.isEmpty, "rec_id <= lastRecID não deve ressuscitar")

        mirror.clearHistory()
        mirror.ingest(rows: [firstRow], emit: false)
        XCTAssertTrue(mirror.recent.isEmpty, "clearHistory também não deve ressuscitar")

        let secondRow = row(rec: 2, bundleID: bundleID, title: "Grupo", body: "Reunião")
        mirror.ingest(rows: [secondRow], emit: false)
        XCTAssertEqual(mirror.recent.map(\.id), [2])
    }
}
