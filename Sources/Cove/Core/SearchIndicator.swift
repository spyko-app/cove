import Foundation

/// O que aparece à esquerda do campo de busca: a lupa de sempre ou o orb girando.
/// Regra pura (sem SwiftUI) pra ser testável: orb só enquanto processa.
enum SearchIndicator: Equatable {
    case glass
    case orb

    static func resolve(isSearching: Bool) -> SearchIndicator {
        isSearching ? .orb : .glass
    }
}
