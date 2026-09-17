import XCTest
@testable import Cove

final class SearchActionsTests: XCTestCase {
    func testShortcutHints() {
        XCTAssertEqual(SearchActions.shortcutHint(for: .open), "Abrir ⏎")
        XCTAssertEqual(SearchActions.shortcutHint(for: .reveal), "Revelar no Finder ⌘R")
        XCTAssertEqual(SearchActions.shortcutHint(for: .quickLook), "Quick Look ␣")
        XCTAssertEqual(SearchActions.shortcutHint(for: .copyPath), "Copiar caminho ⌘C")
        XCTAssertEqual(SearchActions.shortcutHint(for: .sendToShelf), "Enviar pra Cesta ⌘S")
    }

    func testSelectionMoveClamps() {
        XCTAssertEqual(SearchActions.selectionMove(count: 5, index: 2, delta: 1), 3)
        XCTAssertEqual(SearchActions.selectionMove(count: 5, index: 4, delta: 1), 4)
        XCTAssertEqual(SearchActions.selectionMove(count: 5, index: 0, delta: -1), 0)
        XCTAssertEqual(SearchActions.selectionMove(count: 0, index: 0, delta: 1), 0)
        XCTAssertEqual(SearchActions.selectionMove(count: 3, index: 1, delta: -1), 0)
    }

    func testShouldPreviewOnSpace() {
        XCTAssertFalse(SearchActions.shouldPreviewOnSpace(fieldFocused: true, hasSelection: true))
        XCTAssertFalse(SearchActions.shouldPreviewOnSpace(fieldFocused: false, hasSelection: false))
        XCTAssertFalse(SearchActions.shouldPreviewOnSpace(fieldFocused: true, hasSelection: false))
        XCTAssertTrue(SearchActions.shouldPreviewOnSpace(fieldFocused: false, hasSelection: true))
    }
}
