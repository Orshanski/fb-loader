import SwiftUI

struct AuthorsListView: View {
    let library: Library
    let filterText: String
    /// Current language filter from `AppState.languageFilter`. The sentinel
    /// `BooksByContext.unspecifiedLanguageToken` ("__none__") means "no
    /// language tag in INPX", which we map to "" for lookup.
    let languageFilter: String
    @Binding var selectedAuthorID: Int32?

    /// Cached filter result. Recomputed off-main when `filterText` or
    /// `languageFilter` change — must NOT run on the main thread.
    @State private var filtered: [Author] = []

    /// Combined task key so `.task(id:)` re-runs when either input changes.
    private var filterKey: String { "\(languageFilter)|\(filterText)" }

    var body: some View {
        let langKey = languageFilter == BooksByContext.unspecifiedLanguageToken
            ? ""
            : languageFilter
        LazyListTable(items: filtered, selectedID: $selectedAuthorID) { a in
            let count = library.bookCountByAuthorByLang[a.id]?[langKey] ?? 0
            return "\(a.displayName) (\(count))"
        }
        .task(id: filterKey) { await reloadFilter() }
    }

    /// `.task(id:)` cancels-and-restarts when filter inputs change. Sleep
    /// before computing so rapid typing doesn't spawn N concurrent filter
    /// tasks; a 150 ms quiet window means the actual scan only fires once
    /// the user pauses.
    private func reloadFilter() async {
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }

        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        let langKey = languageFilter == BooksByContext.unspecifiedLanguageToken
            ? ""
            : languageFilter
        let lib = library
        let result: [Author] = await Task.detached(priority: .userInitiated) {
            var out: [Author] = []
            out.reserveCapacity(64)
            for i in lib.authors.indices {
                let a = lib.authors[i]
                // Skip authors with no books in the selected language.
                guard (lib.bookCountByAuthorByLang[a.id]?[langKey] ?? 0) > 0 else { continue }
                if !needle.isEmpty,
                   !lib.lowercasedAuthorNames[i].contains(needle) { continue }
                out.append(a)
            }
            return out
        }.value
        if Task.isCancelled { return }
        filtered = result
    }
}
