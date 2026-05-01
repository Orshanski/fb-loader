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
    /// Time at which filterText last changed — for measuring full pipeline
    /// latency (keystroke → user-visible UI update).
    @State private var keystrokeAt: ContinuousClock.Instant?

    var body: some View {
        let _ = print("[AuthorsListView] body @\(ContinuousClock.now) filterText='\(filterText)' filtered.count=\(filtered.count)")
        // SwiftUI Table chokes on 166k → N transitions (~20 s for one diff).
        // LazyListTable wraps NSTableView, which doesn't diff — reloadData is
        // O(1) and rows are fetched lazily for the visible viewport.
        LazyListTable(items: filtered, selectedID: $selectedAuthorID) { a in
            let count = library.bookCountByAuthor[a.id, default: 0]
            return "\(a.displayName) (\(count))"
        }
        .onChange(of: filterText) { _, new in
            print("[AuthorsListView] filterText onChange → '\(new)' @\(ContinuousClock.now)")
            keystrokeAt = ContinuousClock.now
        }
        .onChange(of: filtered.count) { _, newCount in
            print("[AuthorsListView] filtered.count onChange → \(newCount) @\(ContinuousClock.now)")
            if let t = keystrokeAt {
                print("[AuthorsListView] keystroke→Table updated (\(newCount) rows): \(ContinuousClock.now - t)")
                keystrokeAt = nil
            }
        }
        .task(id: filterText) {
            print("[AuthorsListView] .task body fires for filterText='\(filterText)' @\(ContinuousClock.now)")
            await reloadFilter()
        }
    }

    /// `.task(id:)` cancels-and-restarts when `filterText` changes. Sleep
    /// before computing so rapid typing doesn't spawn N concurrent filter
    /// tasks; a 150 ms quiet window means the actual scan only fires once
    /// the user pauses. No cap — `LazyListTable`/`NSTableView` handles
    /// hundreds of thousands of rows lazily.
    private func reloadFilter() async {
        let beforeSleep = ContinuousClock.now
        try? await Task.sleep(for: .milliseconds(150))
        print("[AuthorsListView] post-sleep @\(ContinuousClock.now), slept \(ContinuousClock.now - beforeSleep)")
        if Task.isCancelled { print("[AuthorsListView] cancelled after sleep"); return }

        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        let lib = library
        let started = ContinuousClock.now
        print("[AuthorsListView] entering Task.detached scan for '\(needle)' @\(started)")
        let result: [Author] = await Task.detached(priority: .userInitiated) {
            if needle.isEmpty { return lib.authors }
            var out: [Author] = []
            out.reserveCapacity(64)
            for i in lib.authors.indices
            where lib.lowercasedAuthorNames[i].contains(needle) {
                out.append(lib.authors[i])
            }
            return out
        }.value
        let elapsed = ContinuousClock.now - started
        print("[AuthorsListView] scan returned \(result.count) in \(elapsed) @\(ContinuousClock.now)")
        if Task.isCancelled { print("[AuthorsListView] cancelled after scan"); return }
        let assignAt = ContinuousClock.now
        filtered = result
        print("[AuthorsListView] filtered = result done @\(ContinuousClock.now), assign took \(ContinuousClock.now - assignAt)")
    }
}
