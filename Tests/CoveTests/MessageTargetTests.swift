import XCTest
@testable import Cove

final class MessageTargetTests: XCTestCase {
    func testPhoneNormalizedWithLeadingPlus() {
        let ddi = MessageTarget.countryCallingCode(for: Locale.current.region?.identifier) ?? ""
        XCTAssertEqual(MessageTarget.handle(fromNotificationTitle: "(11) 98888-7777", body: ""), "+\(ddi)11988887777")
        XCTAssertEqual(MessageTarget.countryCallingCode(for: "BR"), "55")
        XCTAssertNil(MessageTarget.countryCallingCode(for: "ZZ"))
        XCTAssertEqual(MessageTarget.handle(fromNotificationTitle: "+55 11 98888-7777", body: ""), "+5511988887777")
    }

    func testEmailLowercased() {
        XCTAssertEqual(MessageTarget.handle(fromNotificationTitle: "John@Example.com", body: "oi"), "john@example.com")
    }

    func testContactNameReturnsNil() {
        XCTAssertNil(MessageTarget.handle(fromNotificationTitle: "João Silva", body: "oi"))
        XCTAssertNil(MessageTarget.handle(fromNotificationTitle: "", body: ""))
    }
}
