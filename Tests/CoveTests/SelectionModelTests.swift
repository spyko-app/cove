import XCTest
@testable import Cove

final class SelectionModelTests: XCTestCase {
    let ordered = [1, 2, 3, 4, 5]

    func testPlainClickSelectsOnlyOne() {
        var m = SelectionModel<Int>()
        m.click(2, ordered: ordered, shift: false, command: false)
        XCTAssertEqual(m.selected, [2])
        XCTAssertEqual(m.anchor, 2)
        m.click(4, ordered: ordered, shift: false, command: false)
        XCTAssertEqual(m.selected, [4])
        XCTAssertEqual(m.anchor, 4)
    }

    func testCommandTogglesOn() {
        var m = SelectionModel<Int>()
        m.click(2, ordered: ordered, shift: false, command: true)
        XCTAssertEqual(m.selected, [2])
        XCTAssertEqual(m.anchor, 2)
        m.click(3, ordered: ordered, shift: false, command: true)
        XCTAssertEqual(m.selected, [2, 3])
        XCTAssertEqual(m.anchor, 3)
    }

    func testCommandTogglesOff() {
        var m = SelectionModel<Int>()
        m.click(2, ordered: ordered, shift: false, command: true)
        m.click(3, ordered: ordered, shift: false, command: true)
        m.click(2, ordered: ordered, shift: false, command: true)
        XCTAssertEqual(m.selected, [3])
    }

    func testShiftRangeForward() {
        var m = SelectionModel<Int>()
        m.click(2, ordered: ordered, shift: false, command: false)
        m.click(4, ordered: ordered, shift: true, command: false)
        XCTAssertEqual(m.selected, [2, 3, 4])
        XCTAssertEqual(m.anchor, 2)
    }

    func testShiftRangeBackward() {
        var m = SelectionModel<Int>()
        m.click(4, ordered: ordered, shift: false, command: false)
        m.click(2, ordered: ordered, shift: true, command: false)
        XCTAssertEqual(m.selected, [2, 3, 4])
        XCTAssertEqual(m.anchor, 4)
    }

    func testShiftWithoutAnchorActsAsPlainClick() {
        var m = SelectionModel<Int>()
        m.click(3, ordered: ordered, shift: true, command: false)
        XCTAssertEqual(m.selected, [3])
        XCTAssertEqual(m.anchor, 3)
    }

    func testClearResetsSelectionAndAnchor() {
        var m = SelectionModel<Int>()
        m.click(2, ordered: ordered, shift: false, command: true)
        m.clear()
        XCTAssertTrue(m.selected.isEmpty)
        XCTAssertNil(m.anchor)
    }

    func testIsSelectedReflectsState() {
        var m = SelectionModel<Int>()
        m.click(2, ordered: ordered, shift: false, command: true)
        XCTAssertTrue(m.isSelected(2))
        XCTAssertFalse(m.isSelected(3))
    }

    /// `selectOnly` colapsa qualquer seleção múltipla pra um único item e vira âncora —
    /// usado pela navegação por teclado (T22 #1) sem depender de `ordered`.
    func testSelectOnlyCollapsesMultiSelection() {
        var m = SelectionModel<Int>()
        m.click(2, ordered: ordered, shift: false, command: true)
        m.click(3, ordered: ordered, shift: false, command: true)
        XCTAssertEqual(m.selected, [2, 3])
        m.selectOnly(5)
        XCTAssertEqual(m.selected, [5])
        XCTAssertEqual(m.anchor, 5)
    }
}
