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
        List(selection: $selectedAuthorID) {
            ForEach(visibleAuthors) { a in
                let count = library.bookCountByAuthor[a.id, default: 0]
                Text("\(a.displayName) (\(count))")
                    .tag(Int32?.some(a.id))
            }
        }
    }
}
