import Foundation

/// Contador de referência genérico: `retain()` chama `onFirst` só na
/// transição 0→1, `release()` chama `onLast` só na transição 1→0. Usado por
/// serviços compartilhados por mais de um painel (`SystemStats`, `ShelfStore`)
/// pra que o `onDisappear` de UM painel não mate o serviço que o OUTRO ainda
/// está usando (auditoria #31).
@MainActor
final class ActiveCount {
    private(set) var count = 0
    private let onFirst: () -> Void
    private let onLast: () -> Void

    init(onFirst: @escaping () -> Void, onLast: @escaping () -> Void) {
        self.onFirst = onFirst
        self.onLast = onLast
    }

    func retain() {
        count = Self.nextCount(count, retain: true)
        if count == 1 { onFirst() }
    }

    func release() {
        let previous = count
        count = Self.nextCount(count, retain: false)
        if previous == 1, count == 0 { onLast() }
    }

    /// Próximo valor do contador — pura, testável sem side effects.
    /// `retain: false` nunca deixa o contador ficar negativo (release
    /// sobrando não derruba um `retain()` futuro).
    nonisolated static func nextCount(_ current: Int, retain: Bool) -> Int {
        retain ? current + 1 : max(0, current - 1)
    }
}
