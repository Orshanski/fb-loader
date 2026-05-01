import SwiftUI

struct AuthorsListView: View {
    let library: Library
    let filterText: String
    @Binding var selectedAuthorID: Int32?

    /// Cached filter result. Recomputed off-main when `filterText` changes —
    /// the filter loop over 100k+ authors must NOT run on the main thread,
    /// otherwise every keystroke freezes the UI even with precomputed
    /// lowercased names.
    @State private var filtered: [Author] = []

    var body: some View {
        // `Table` is backed by NSTableView and properly virtualizes 100k+
        // rows. SwiftUI `List` over a flat ForEach diffs the entire identity
        // tree on every render and chokes at this scale. Single column,
        // headers hidden — visually identical to a list.
        Table(filtered, selection: $selectedAuthorID) {
            TableColumn("Автор") { (a: Author) in
                let count = library.bookCountByAuthor[a.id, default: 0]
                Text("\(a.displayName) (\(count))")
            }
        }
        .tableColumnHeaders(.hidden)
        .task(id: filterText) {
            await reloadFilter()
        }
    }

    /// Hard cap so the Table never has to materialize more than ~few hundred
    /// rows after a filter — for the user, a longer "needle" returning
    /// thousands of matches is useless anyway.
    private static let maxResults = 500

    /// `.task(id:)` cancels-and-restarts when `filterText` changes. Sleep
    /// before computing so rapid typing doesn't spawn N concurrent filter
    /// tasks; a 150 ms quiet window means the actual scan only fires once
    /// the user pauses.
    private func reloadFilter() async {
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }

        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        let lib = library
        let cap = Self.maxResults
        let started = ContinuousClock.now
        let result: [Author] = await Task.detached(priority: .userInitiated) {
            if needle.isEmpty { return lib.authors }
            var out: [Author] = []
            out.reserveCapacity(cap)
            for i in lib.authors.indices {
                if lib.lowercasedAuthorNames[i].contains(needle) {
                    out.append(lib.authors[i])
                    if out.count >= cap { break }
                }
            }
            return out
        }.value
        let elapsed = ContinuousClock.now - started
        print("[AuthorsListView] filter '\(needle)' over \(lib.authors.count) → \(result.count) in \(elapsed)")
        if Task.isCancelled { return }
        filtered = result
    }
}
