import SwiftUI

struct AuthorsListView: View {
    let library: Library
    let filterText: String
    @Binding var selectedAuthorID: Int32?

    private var visibleAuthors: [Author] {
        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        if needle.isEmpty { return library.authors }
        // Match against precomputed lowercased names (`Library.lowercasedAuthorNames`)
        // so we don't reallocate 100k+ lowercased strings on every keystroke.
        var result: [Author] = []
        result.reserveCapacity(64)
        for i in library.authors.indices
        where library.lowercasedAuthorNames[i].contains(needle) {
            result.append(library.authors[i])
        }
        return result
    }

    var body: some View {
        // `Table` is backed by NSTableView and properly virtualizes 100k+
        // rows. SwiftUI `List` over a flat ForEach diffs the entire identity
        // tree on every render and chokes at this scale. Single column,
        // headers hidden — visually identical to a list.
        Table(visibleAuthors, selection: $selectedAuthorID) {
            TableColumn("Автор") { (a: Author) in
                let count = library.bookCountByAuthor[a.id, default: 0]
                Text("\(a.displayName) (\(count))")
            }
        }
        .tableColumnHeaders(.hidden)
    }
}
