import Foundation

/// Matemática pura da arte em movimento (sem SwiftUI) — suavização dos níveis
/// do waveform e cálculo de energia média, usados pelo `MotionArtView`.
enum MotionMath {
    /// Média móvel exponencial entre o estado anterior e o novo nível.
    /// `alpha` 1 = usa `next` puro; `alpha` 0 = mantém `prev`. Índices sem par
    /// em `prev` caem direto no valor de `next`.
    static func smooth(prev: [Float], next: [Float], alpha: Float) -> [Float] {
        let a = min(max(alpha, 0), 1)
        return next.enumerated().map { i, value in
            guard i < prev.count else { return value }
            return prev[i] + (value - prev[i]) * a
        }
    }

    /// Energia média das bandas, sempre entre 0 e 1.
    static func energy(_ levels: [Float]) -> Float {
        guard !levels.isEmpty else { return 0 }
        let sum = levels.reduce(0, +)
        let avg = sum / Float(levels.count)
        return min(max(avg, 0), 1)
    }
}
