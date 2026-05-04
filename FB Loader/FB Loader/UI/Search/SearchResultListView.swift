import SwiftUI

/// Sectioned scroll layout for search results: Авторы / Серии / Совпадения по книгам.
/// Routes per-group rendering to dedicated block views.
struct SearchResultListView: View {
    @Bindable var coord: SearchCoordinator
    let library: Library
    let results: SearchResults
    let onRequestExport: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                // Authors group
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
                            onRequestExport: onRequestExport
                        )
                    }
                    if results.authors.count > coord.visibleAuthorsCount {
                        Button("Показать всех (\(results.authors.count))") {
                            coord.visibleAuthorsCount = .max
                        }
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    Divider().padding(.vertical, 6)
                }

                // Series group
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
                            onRequestExport: onRequestExport
                        )
                    }
                    if results.series.count > coord.visibleSeriesCount {
                        Button("Показать все (\(results.series.count))") {
                            coord.visibleSeriesCount = .max
                        }
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    Divider().padding(.vertical, 6)
                }

                // Books bucket
                if !results.books.isEmpty {
                    SearchBooksBucketView(
                        coord: coord,
                        library: library,
                        bookHits: results.books,
                        onRequestExport: onRequestExport
                    )
                }
            }
        }
    }
}
