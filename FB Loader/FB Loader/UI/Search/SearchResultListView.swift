import SwiftUI

struct SearchResultListView: View {
    @Bindable var coord: SearchCoordinator
    let library: Library
    let results: SearchResults
    let exportSession: ExportSession
    let onRequestExport: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                if !results.authors.isEmpty {
                    Text("Авторы")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    let visible = results.authors.prefix(coord.visibleAuthorsCount)
                    ForEach(Array(visible.enumerated()), id: \.element.authorIndex) { _, m in
                        SearchAuthorBlock(
                            coord: coord,
                            library: library,
                            authorIndex: m.authorIndex,
                            exportSession: exportSession,
                            onRequestExport: onRequestExport
                        )
                    }
                    if results.authors.count > coord.visibleAuthorsCount {
                        Button("Показать всех авторов (\(results.authors.count))") {
                            coord.visibleAuthorsCount = .max
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    Divider().padding(.vertical, 6)
                }

                if !results.series.isEmpty {
                    Text("Серии")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                    let visible = results.series.prefix(coord.visibleSeriesCount)
                    ForEach(Array(visible.enumerated()), id: \.element.seriesIndex) { _, m in
                        SearchSeriesBlock(
                            coord: coord,
                            library: library,
                            seriesIndex: m.seriesIndex,
                            exportSession: exportSession,
                            onRequestExport: onRequestExport
                        )
                    }
                    if results.series.count > coord.visibleSeriesCount {
                        Button("Показать все серии (\(results.series.count))") {
                            coord.visibleSeriesCount = .max
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    Divider().padding(.vertical, 6)
                }

                if !results.books.isEmpty {
                    SearchBooksBucketView(
                        coord: coord,
                        library: library,
                        bookHits: results.books,
                        exportSession: exportSession,
                        onRequestExport: onRequestExport
                    )
                }
            }
        }
    }
}
