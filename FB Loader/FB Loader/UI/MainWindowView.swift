import SwiftUI

struct MainWindowView: View {
    let library: Library
    @Environment(AppState.self) private var state

    var body: some View {
        HSplitView {
            LeftSidebarView(library: library)
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
            VSplitView {
                BooksTableView(library: library)
                    .frame(minHeight: 200)
                if let libid = state.selectedBookLibid,
                   let book = library.books.first(where: { $0.libid == libid }),
                   let archives = state.userPaths.archivesDirectoryURL {
                    BookDetailView(library: library, archivesRoot: archives, book: book)
                        .frame(minHeight: 200)
                } else {
                    Text("Выберите книгу").foregroundStyle(.secondary).frame(minHeight: 200)
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
    }
}
