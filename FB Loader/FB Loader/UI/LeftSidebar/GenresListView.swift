import SwiftUI

struct GenresListView: View {
    let library: Library
    let filterText: String
    let languageFilter: String
    @Binding var selectedGenreID: Int16?

    var body: some View {
        let langKey = BooksByContext.languageKey(languageFilter)
        let counts = library.bookCountByGenreByLang
        let orphanIDs = Set(library.orphanGenres.map(\.id))
        let childrenByRoot = library.childGenresByParent
        let lowercasedNames = library.lowercasedGenreNames
        FilteredSidebarList(
            items: library.sidebarGenres,
            lowercasedNames: library.lowercasedSidebarGenreNames,
            countFor: { g in counts[g.id]?[langKey] ?? 0 },
            labelFor: { g in g.name },
            trailingLabelFor: { g in
                let count = counts[g.id]?[langKey] ?? 0
                return count == 0 && g.parentID == nil ? "" : "\(count)"
            },
            includeZeroCountItem: { g, pattern in
                guard g.parentID == nil else { return false }
                return childrenByRoot[g.id]?.contains { child in
                    guard (counts[child.id]?[langKey] ?? 0) > 0,
                          let name = lowercasedNames[child.id] else { return false }
                    return pattern.matches(name)
                } ?? false
            },
            rowStyleFor: { g in
                if g.parentID == nil {
                    return SidebarRowStyle(leadingInset: 14, fontWeight: .semibold)
                }
                if orphanIDs.contains(g.id) {
                    return SidebarRowStyle()
                }
                return SidebarRowStyle(leadingInset: 32)
            },
            selectedID: $selectedGenreID,
            filterText: filterText,
            filterKey: "\(languageFilter)|\(filterText)",
            memoryKey: "genres"
        )
    }
}
