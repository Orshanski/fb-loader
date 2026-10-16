import SwiftUI

struct SeriesListView: View {
    let library: Library
    let filterText: String
    let languageFilter: String
    @Binding var selectedSeriesID: Int32?

    var body: some View {
        let langKey = BooksByContext.languageKey(languageFilter)
        FilteredSidebarList(
            items: library.series,
            lowercasedNames: library.lowercasedSeriesNames,
            countFor: { s in library.bookCount(seriesID: s.id, language: langKey) },
            labelFor: { s in s.name },
            trailingLabelFor: { s in "\(library.bookCount(seriesID: s.id, language: langKey))" },
            selectedID: $selectedSeriesID,
            filterText: filterText,
            filterKey: "\(languageFilter)|\(filterText)",
            memoryKey: "series"
        )
    }
}
