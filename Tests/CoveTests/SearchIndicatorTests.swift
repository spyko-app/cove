import XCTest
@testable import Cove

final class SearchIndicatorTests: XCTestCase {
    func testGlassWhenIdle() {
        XCTAssertEqual(SearchIndicator.resolve(isSearching: false), .glass)
    }

    func testOrbWhileSearching() {
        XCTAssertEqual(SearchIndicator.resolve(isSearching: true), .orb)
    }

    @MainActor
    func testSpotlightStartsIdle() {
        XCTAssertFalse(SpotlightSearch().isSearching)
    }

    @MainActor
    func testSearchingFlagsOrbAndEmptyQueryClearsIt() {
        let s = SpotlightSearch()
        s.search("relatorio")
        XCTAssertEqual(SearchIndicator.resolve(isSearching: s.isSearching), .orb)
        s.search("   ")
        XCTAssertEqual(SearchIndicator.resolve(isSearching: s.isSearching), .glass)
    }

    @MainActor
    func testCancelStopsOrb() {
        let s = SpotlightSearch()
        s.search("x")
        s.cancel()
        XCTAssertFalse(s.isSearching)
    }
}
