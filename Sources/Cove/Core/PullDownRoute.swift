import Foundation

/// Para onde vai o gesto de puxar a ilha FECHADA pra baixo (padrão iOS 27:
/// "Search or Ask"). Regra pura, sem SwiftUI, pra o `NotchPanel` só executar.
enum PullDownRoute: Equatable {
    /// Abre direto na página Busca, campo já focado.
    case search
    /// Abre a ilha como sempre (opção desligada, ou Busca desligada nos Ajustes —
    /// pedir a página aí só renderia o aviso "Busca está desligado").
    case expand

    static func target(opensSearch: Bool, searchEnabled: Bool) -> PullDownRoute {
        opensSearch && searchEnabled ? .search : .expand
    }
}
