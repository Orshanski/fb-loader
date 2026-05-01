import SwiftUI

struct SeriesListView: View {
    let library: Library
    let filterText: String
    let languageFilter: String
    @Binding var selectedSeriesID: Int32?

    @State private var filtered: [Series] = []

    private var filterKey: String { "\(languageFilter)|\(filterText)" }

    var body: some View {
        let langKey = languageFilter == BooksByContext.unspecifiedLanguageToken
            ? ""
            : languageFilter
        LazyListTable(items: filtered, selectedID: $selectedSeriesID) { s in
            let count = library.bookCountBySeriesByLang[s.id]?[langKey] ?? 0
            return "\(s.name) (\(count))"
        }
        .task(id: filterKey) { await reloadFilter() }
    }

    /// Same off-main + 150 ms debounce as AuthorsListView, plus language gate.
    private func reloadFilter() async {
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }

        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        let langKey = languageFilter == BooksByContext.unspecifiedLanguageToken
            ? ""
            : languageFilter
        let lib = library
        let result: [Series] = await Task.detached(priority: .userInitiated) {
            var out: [Series] = []
            out.reserveCapacity(64)
            for i in lib.series.indices {
                let s = lib.series[i]
                guard (lib.bookCountBySeriesByLang[s.id]?[langKey] ?? 0) > 0 else { continue }
                if !needle.isEmpty,
                   !lib.lowercasedSeriesNames[i].contains(needle) { continue }
                out.append(s)
            }
            return out
        }.value
        if Task.isCancelled { return }
        filtered = result
    }
}
