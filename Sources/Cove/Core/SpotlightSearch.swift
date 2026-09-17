import AppKit

@MainActor
final class SpotlightSearch: ObservableObject {
    struct Result: Identifiable, Equatable { let id: URL; let name: String; let kind: String }

    @Published private(set) var results: [Result] = []
    @Published private(set) var isSearching = false
    private var query: NSMetadataQuery?
    private var debounce: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    func search(_ text: String) {
        debounce?.cancel()
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { cancel(); return }
        isSearching = true
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.run(t)
        }
    }

    func cancel() {
        debounce?.cancel(); debounce = nil
        stopQuery()
        results = []
        isSearching = false
    }

    private func stopQuery() {
        query?.stop()
        query = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func run(_ t: String) {
        stopQuery()
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@ OR kMDItemTextContent CONTAINS[cd] %@", t, t)
        q.searchScopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        let finish = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self, let q = self.query else { return }; self.collect(q) }
        }
        let update = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self, let q = self.query else { return }; self.collect(q) }
        }
        observers = [finish, update]
        q.start()
        query = q
    }

    private func collect(_ q: NSMetadataQuery) {
        q.disableUpdates()
        results = (0..<min(q.resultCount, 30)).compactMap { i in
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            let url = URL(fileURLWithPath: path)
            return Result(id: url,
                          name: item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String ?? url.lastPathComponent,
                          kind: item.value(forAttribute: NSMetadataItemKindKey) as? String ?? "")
        }
        q.enableUpdates()
        isSearching = false
    }
}
