struct SelectionModel<ID: Hashable> {
    private(set) var selected: Set<ID> = []
    var anchor: ID?

    init() {}

    mutating func click(_ id: ID, ordered: [ID], shift: Bool, command: Bool) {
        if shift, let anchor, let from = ordered.firstIndex(of: anchor), let to = ordered.firstIndex(of: id) {
            let range = from <= to ? from...to : to...from
            selected = Set(ordered[range])
            return
        }
        if command {
            if selected.contains(id) {
                selected.remove(id)
            } else {
                selected.insert(id)
                anchor = id
            }
            return
        }
        selected = [id]
        anchor = id
    }

    mutating func clear() {
        selected.removeAll()
        anchor = nil
    }

    mutating func selectOnly(_ id: ID) {
        selected = [id]
        anchor = id
    }

    func isSelected(_ id: ID) -> Bool { selected.contains(id) }
}
