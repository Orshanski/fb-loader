import SwiftUI

/// Header subtitle: the series' «основной» author and book count.
struct SearchSeriesBlock: View {
    @Bindable var coord: SearchCoordinator
    let library: Library
    let seriesIndex: Int
    let exportSession: ExportSession
    let onRequestExport: () -> Void

    private let defaultBooksLimit = 5

    private var series: Series { library.series[seriesIndex] }
    private var collapsed: Bool { coord.collapsedSeries.contains(seriesIndex) }
    private var fullyExpanded: Bool { coord.fullyExpandedSeries.contains(seriesIndex) }

    private var booksInLanguage: [Book] {
        BooksByContext.books(for: .series(series.id),
                             language: coord.languageFilter,
                             in: library)
            .sorted { ($0.seriesNum ?? Int16.max) < ($1.seriesNum ?? Int16.max) }
    }

    /// «Основной» автор серии — автор её первой книги в текущем языке.
    private var primaryAuthor: Author? {
        guard let first = booksInLanguage.first,
              let aid = first.authorIDs.first
        else { return nil }
        return library.author(id: aid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !collapsed { booksList }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("серия").foregroundStyle(.secondary)
            Text(series.name).fontWeight(.semibold)
            Spacer()
            if let author = primaryAuthor {
                Text("\(author.displayName) — \(booksCountLabel(booksInLanguage.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if collapsed { coord.collapsedSeries.remove(seriesIndex) }
            else         { coord.collapsedSeries.insert(seriesIndex) }
        }
    }


    @ViewBuilder
    private var booksList: some View {
        let allBooks = booksInLanguage
        let visibleBooks = fullyExpanded ? allBooks : Array(allBooks.prefix(defaultBooksLimit))
        ForEach(visibleBooks, id: \.libid) { b in
            BookRow(
                book: b, library: library, indented: true,
                coord: coord,
                contextMenuBuilder: { exportContextMenu() }
            )
        }
        if !fullyExpanded && allBooks.count > defaultBooksLimit {
            Button("Показать все книги серии (\(allBooks.count))") {
                coord.fullyExpandedSeries.insert(seriesIndex)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 30)
            .padding(.vertical, 6)
        }
    }

    private func exportContextMenu() -> AnyView {
        AnyView(
            SearchExportMenu(checkedCount: coord.checkedBookLibids.count,
                             isBusy: exportSession.isBusy, onExport: onRequestExport)
        )
    }
}
