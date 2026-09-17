import XCTest
@testable import Cove

final class CaptureAnnotationsTests: XCTestCase {
    func testAddArrowNoNumber() {
        var doc = AnnotationDocument()
        doc.add(tool: .arrow, from: .zero, to: CGPoint(x: 10, y: 10), color: "red")
        XCTAssertEqual(doc.annotations.count, 1)
        XCTAssertNil(doc.annotations[0].number)
        XCTAssertEqual(doc.annotations[0].tool, .arrow)
    }

    func testAddBadgeAutoNumbers() {
        var doc = AnnotationDocument()
        doc.add(tool: .badge, from: .zero, to: .zero, color: "blue")
        doc.add(tool: .rect, from: .zero, to: .zero, color: "blue")
        doc.add(tool: .badge, from: .zero, to: .zero, color: "blue")
        doc.add(tool: .badge, from: .zero, to: .zero, color: "blue")
        let badgeNumbers = doc.annotations.filter { $0.tool == .badge }.map(\.number)
        XCTAssertEqual(badgeNumbers, [1, 2, 3])
    }

    func testUndoRemovesLastAndRenumbers() {
        var doc = AnnotationDocument()
        doc.add(tool: .badge, from: .zero, to: .zero, color: "blue")
        doc.add(tool: .badge, from: .zero, to: .zero, color: "blue")
        doc.add(tool: .badge, from: .zero, to: .zero, color: "blue")
        let removed = doc.undo()
        XCTAssertEqual(removed?.number, 3)
        XCTAssertEqual(doc.annotations.count, 2)
        XCTAssertEqual(doc.annotations.map(\.number), [1, 2])
    }

    func testUndoOnlyRemovesLastKeepingOrderOfEarlierBadges() {
        var doc = AnnotationDocument()
        doc.add(tool: .badge, from: .zero, to: .zero, color: "blue")
        doc.add(tool: .rect, from: .zero, to: .zero, color: "blue")
        doc.add(tool: .badge, from: .zero, to: .zero, color: "blue")
        doc.undo()
        XCTAssertEqual(doc.annotations.count, 2)
        XCTAssertEqual(doc.annotations.filter { $0.tool == .badge }.map(\.number), [1])
    }

    func testUndoOnEmptyReturnsNil() {
        var doc = AnnotationDocument()
        XCTAssertNil(doc.undo())
    }

    func testClearRemovesEverything() {
        var doc = AnnotationDocument()
        doc.add(tool: .badge, from: .zero, to: .zero, color: "blue")
        doc.add(tool: .arrow, from: .zero, to: .zero, color: "blue")
        doc.clear()
        XCTAssertTrue(doc.annotations.isEmpty)
    }

    func testBackgroundAndPaddingDefaults() {
        let doc = AnnotationDocument()
        XCTAssertEqual(doc.background, .none)
        XCTAssertEqual(doc.padding, 0)
    }

    func testStrokeScaleWhenExportLargerThanPreview() {
        let scale = AnnotationDocument.strokeScale(exportWidth: 1800, previewWidth: 900)
        XCTAssertEqual(scale, 2)
    }

    func testStrokeScaleNeverGoesBelowOne() {
        let scale = AnnotationDocument.strokeScale(exportWidth: 400, previewWidth: 900)
        XCTAssertEqual(scale, 1)
    }

    func testStrokeScaleWithZeroPreviewWidthFallsBackToOne() {
        let scale = AnnotationDocument.strokeScale(exportWidth: 1800, previewWidth: 0)
        XCTAssertEqual(scale, 1)
    }

    func testUniqueExportNameWithoutConflict() {
        let name = ExportNaming.uniqueExportName(base: "shot") { _ in false }
        XCTAssertEqual(name, "shot-editado.png")
    }

    func testUniqueExportNameIncrementsUntilFree() {
        let taken: Set<String> = ["shot-editado.png", "shot-editado-2.png"]
        let name = ExportNaming.uniqueExportName(base: "shot") { taken.contains($0) }
        XCTAssertEqual(name, "shot-editado-3.png")
    }
}
