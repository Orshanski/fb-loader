import SwiftUI

/// Collapsible «автор» block; books are laid out as in `BooksTableView` for a selected author:
/// loose books first, then series groups.
struct SearchAuthorBlock: View {
    @Bindable var coord: SearchCoordinator
    let library: Library
    let authorIndex: Int
    let exportSession: ExportSession
    let onRequestExport: () -> Void

    private let defaultBooksLimit = 10

    private var author: Author { library.authors[authorIndex] }
    private var collapsed: Bool { coord.collapsedAuthors.contains(authorIndex) }
    private var fullyExpanded: Bool { coord.fullyExpandedAuthors.contains(authorIndex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !collapsed { groupedBooks }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("автор").foregroundStyle(.secondary)
            Text(author.displayName).fontWeight(.semibold)
            Spacer()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if collapsed { coord.collapsedAuthors.remove(authorIndex) }
            else         { coord.collapsedAuthors.insert(authorIndex) }
        }
    }

    @ViewBuilder
    private var groupedBooks: some View {
        let allBooks = BooksByContext.books(for: .author(author.id),
                                            language: coord.languageFilter,
                                            in: library)
        let visibleBooks = fullyExpanded ? allBooks : Array(allBooks.prefix(defaultBooksLimit))
        let (loose, bySeries) = BookGrouping.group(visibleBooks, library: library)
        ForEach(loose, id: \.libid) { b in
            row(for: b, indented: false)
        }
        ForEach(bySeries, id: \.series.id) { group in
            seriesSubHeader(name: group.series.name, count: group.books.count)
            ForEach(group.books, id: \.libid) { b in
                row(for: b, indented: true)
            }
        }
        if !fullyExpanded && allBooks.count > defaultBooksLimit {
            Button("Показать все книги автора (\(allBooks.count))") {
                coord.fullyExpandedAuthors.insert(authorIndex)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 30)
            .padding(.vertical, 6)
        }
    }

    private func row(for b: Book, indented: Bool) -> some View {
        BookRow(
            book: b, library: library, indented: indented,
            coord: coord,
            contextMenuBuilder: { exportContextMenu() }
        )
    }

    private func exportContextMenu() -> AnyView {
        AnyView(
            SearchExportMenu(checkedCount: coord.checkedBookLibids.count,
                             isBusy: exportSession.isBusy, onExport: onRequestExport)
        )
    }

    private func seriesSubHeader(name: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(name).font(.system(size: 13, weight: .semibold))
            Text("(\(count))").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
