import SwiftUI
import XCTest
@testable import Cove

final class NotchShapeTests: XCTestCase {
    func testFlareKeepsBodyInsideFrame() {
        let shape = NotchShape(bottomRadius: 12, topRadius: 10)
        let box = shape.path(in: CGRect(x: 0, y: 0, width: 300, height: 38)).boundingRect
        XCTAssertEqual(box.minX, 0, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 300, accuracy: 0.01)
        XCTAssertEqual(box.maxY, 38, accuracy: 0.01)
    }

    func testTopEdgeSpansFullWidthAtY0() {
        let path = NotchShape(bottomRadius: 12, topRadius: 24)
            .path(in: CGRect(x: 0, y: 0, width: 200, height: 40))
        XCTAssertTrue(path.contains(CGPoint(x: 12, y: 1)))
        XCTAssertFalse(path.contains(CGPoint(x: 12, y: 5)))
        XCTAssertTrue(path.contains(CGPoint(x: 188, y: 1)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 30)))
    }

    func testAnimatableDataRoundTrip() {
        var shape = NotchShape(bottomRadius: 1, topRadius: 2)
        shape.animatableData = AnimatablePair(40, 24)
        XCTAssertEqual(shape.bottomRadius, 40)
        XCTAssertEqual(shape.topRadius, 24)
    }
}
