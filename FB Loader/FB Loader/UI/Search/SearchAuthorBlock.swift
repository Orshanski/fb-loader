import SwiftUI

/// One «автор <имя>» result block. Header is collapsible. When expanded,
/// shows the author's books in the same structure as the main `BooksTableView`
/// when that author is selected: loose books first, then series-grouped
/// sub-sections with seriesNum-sorted books.
struct SearchAuthorBlock: View {
    @Bindable var coord: SearchCoordinator
    let library: Library
    let authorIndex: Int

    private var author: Author { library.authors[authorIndex] }
    private var collapsed: Bool { coord.collapsedAuthors.contains(authorIndex) }

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
        let books = BooksByContext.books(for: .author(author.id),
                                         language: coord.languageFilter,
                                         in: library)
        let (loose, bySeries) = groupBooks(books)
        ForEach(Array(loose.enumerated()), id: \.element.libid) { _, b in
            row(for: b, indented: false)
        }
        ForEach(bySeries, id: \.seriesID) { group in
            seriesSubHeader(name: group.seriesName, count: group.books.count)
            ForEach(group.books, id: \.libid) { b in
                row(for: b, indented: true)
            }
        }
    }

    private func row(for b: Book, indented: Bool) -> some View {
        BookRow(
            book: b, library: library, indented: indented,
            isChecked: bindingChecked(b),
            isSelected: bindingSelected(b)
        )
    }

    private func bindingChecked(_ b: Book) -> Binding<Bool> {
        Binding(
            get: { coord.checkedBookLibids.contains(b.libid) },
            set: { isOn in
                if isOn { coord.checkedBookLibids.insert(b.libid) }
                else    { coord.checkedBookLibids.remove(b.libid) }
            }
        )
    }
    private func bindingSelected(_ b: Book) -> Binding<Bool> {
        Binding(
            get: { coord.selectedBookLibid == b.libid },
            set: { newValue in if newValue { coord.selectedBookLibid = b.libid } }
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

    private struct SeriesGroup { let seriesID: Int32; let seriesName: String; let books: [Book] }

    private func groupBooks(_ books: [Book]) -> (loose: [Book], series: [SeriesGroup]) {
        var loose: [Book] = []
        var bySeries: [Int32: [Book]] = [:]
        for b in books {
            if let sid = b.seriesID { bySeries[sid, default: []].append(b) }
            else { loose.append(b) }
        }
        let groups: [SeriesGroup] = bySeries
            .sorted { (library.seriesByID[$0.key]?.name ?? "") < (library.seriesByID[$1.key]?.name ?? "") }
            .map { (sid, items) in
                let s = library.seriesByID[sid]
                return SeriesGroup(
                    seriesID: sid,
                    seriesName: s?.name ?? "?",
                    books: items.sorted {
                        ($0.seriesNum ?? Int16.max) < ($1.seriesNum ?? Int16.max)
                    }
                )
            }
        return (loose, groups)
    }
}
