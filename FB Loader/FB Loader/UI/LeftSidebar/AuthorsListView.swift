import SwiftUI

struct AuthorsListView: View {
    let library: Library
    let filterText: String
    @Binding var selectedAuthorID: Int32?

    private var visibleAuthors: [Author] {
        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        if needle.isEmpty { return library.authors }
        return library.authors.filter {
            $0.displayName.lowercased().contains(needle)
        }
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
