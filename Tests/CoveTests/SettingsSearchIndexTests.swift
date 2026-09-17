import XCTest
@testable import Cove

final class SettingsSearchIndexTests: XCTestCase {
    func testAccentInsensitiveTitleMatch() {
        let idx = SettingsSearchIndex.coveNotch
        XCTAssertTrue(idx.matches("calendario").contains("Ilha expandida"))
    }

    func testKeywordMatch() {
        let idx = SettingsSearchIndex.coveNotch
        XCTAssertTrue(idx.matches("atalho").contains("Droplets"))
        XCTAssertTrue(idx.matches("atalho").contains("Ações rápidas"))
    }

    func testEmptyQueryReturnsAll() {
        let idx = SettingsSearchIndex.coveNotch
        XCTAssertEqual(idx.matches("").count, idx.entries.count)
    }

    func testLockScreenKeywordsFindTelas() {
        let idx = SettingsSearchIndex.coveNotch
        XCTAssertTrue(idx.matches("tela de bloqueio").contains("Telas"))
        XCTAssertTrue(idx.matches("lock screen").contains("Telas"))
        XCTAssertTrue(idx.matches("bloqueio").contains("Telas"))
    }

    func testLockScreenWidgetKeywordsFindTelas() {
        let idx = SettingsSearchIndex.coveNotch
        XCTAssertTrue(idx.matches("widgets").contains("Telas"))
        XCTAssertTrue(idx.matches("relógio").contains("Telas"))
        XCTAssertTrue(idx.matches("cadeado").contains("Telas"))
        XCTAssertTrue(idx.matches("próximo evento").contains("Telas"))
    }

    func testNoMatchReturnsEmpty() {
        let idx = SettingsSearchIndex.coveNotch
        XCTAssertTrue(idx.matches("xyzxyz-nao-existe").isEmpty)
    }
}
