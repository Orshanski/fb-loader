import SwiftUI

struct AuthorsListView: View {
    let library: Library
    let filterText: String
    /// The sentinel `BooksByContext.unspecifiedLanguageToken` is mapped to "" for lookup.
    let languageFilter: String
    @Binding var selectedAuthorID: Int32?

    var body: some View {
        let langKey = BooksByContext.languageKey(languageFilter)
        FilteredSidebarList(
            items: library.authors,
            lowercasedNames: library.lowercasedAuthorNames,
            countFor: { a in library.bookCount(authorID: a.id, language: langKey) },
            labelFor: { a in a.displayName },
            trailingLabelFor: { a in "\(library.bookCount(authorID: a.id, language: langKey))" },
            selectedID: $selectedAuthorID,
            filterText: filterText,
            filterKey: "\(languageFilter)|\(filterText)",
            memoryKey: "authors"
        )
    }
}
