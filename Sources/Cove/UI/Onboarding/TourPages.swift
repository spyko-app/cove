enum TourPages {
    static func next(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(index + 1, count - 1)
    }

    static func prev(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return max(index - 1, 0)
    }
}
