import XCTest
@testable import Cove

@MainActor final class LinkPreviewCacheTests: XCTestCase {
    func testCacheKeyIsStableAndFileSafe() {
        let a = LinkPreviewCache.cacheKey(for: URL(string: "https://example.com/a")!)
        let a2 = LinkPreviewCache.cacheKey(for: URL(string: "https://example.com/a")!)
        let b = LinkPreviewCache.cacheKey(for: URL(string: "https://example.com/b")!)
        XCTAssertEqual(a, a2)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.allSatisfy { $0.isHexDigit })
        XCTAssertEqual(a.count, 64)
    }

    func testNonHTTPURLIsIgnored() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("linkcards-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let cache = LinkPreviewCache(directory: dir)
        let url = URL(string: "file:///tmp/x")!
        cache.fetch(url)
        XCTAssertNil(cache.preview(for: url))
    }
}
