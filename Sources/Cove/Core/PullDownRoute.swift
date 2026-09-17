import Foundation

enum PullDownRoute: Equatable {
    case search
    case expand

    static func target(opensSearch: Bool, searchEnabled: Bool) -> PullDownRoute {
        opensSearch && searchEnabled ? .search : .expand
    }
}
