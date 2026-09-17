import Foundation

enum MotionMath {
    static func smooth(prev: [Float], next: [Float], alpha: Float) -> [Float] {
        let a = min(max(alpha, 0), 1)
        return next.enumerated().map { i, value in
            guard i < prev.count else { return value }
            return prev[i] + (value - prev[i]) * a
        }
    }

    static func energy(_ levels: [Float]) -> Float {
        guard !levels.isEmpty else { return 0 }
        let sum = levels.reduce(0, +)
        let avg = sum / Float(levels.count)
        return min(max(avg, 0), 1)
    }
}
