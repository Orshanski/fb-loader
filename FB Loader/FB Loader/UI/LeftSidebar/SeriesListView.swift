import SwiftUI

struct SeriesListView: View {
    let library: Library
    let filterText: String
    let languageFilter: String
    @Binding var selectedSeriesID: Int32?

    var body: some View {
        let langKey = languageFilter == BooksByContext.unspecifiedLanguageToken
            ? ""
            : languageFilter
        let counts = library.bookCountBySeriesByLang
        FilteredSidebarList(
            items: library.series,
            lowercasedNames: library.lowercasedSeriesNames,
            countFor: { s in counts[s.id]?[langKey] ?? 0 },
            labelFor: { s in s.name },
            trailingLabelFor: { s in "\(counts[s.id]?[langKey] ?? 0)" },
            selectedID: $selectedSeriesID,
            filterText: filterText,
            filterKey: "\(languageFilter)|\(filterText)"
        )
    }
}
