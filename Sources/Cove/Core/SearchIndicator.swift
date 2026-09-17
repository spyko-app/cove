import Foundation

enum SearchIndicator: Equatable {
    case glass
    case orb

    static func resolve(isSearching: Bool) -> SearchIndicator {
        isSearching ? .orb : .glass
    }
}
