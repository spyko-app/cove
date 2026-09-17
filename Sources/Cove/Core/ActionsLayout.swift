import Foundation

enum ActionsGrid {
    static func columns(for count: Int) -> Int {
        count <= 4 ? max(count, 1) : 4
    }
}
