import SwiftUI

/// «Совпадения по книгам» bucket. Paginated by 20 — «Загрузить ещё +20»
/// extends `coord.visibleBooksCount`.
struct SearchBooksBucketView: View {
    @Bindable var coord: SearchCoordinator
    let library: Library
    let bookHits: [BookMatch]
    let exportSession: ExportSession
    let onRequestExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Совпадения по книгам")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(bookHits.count) шт")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 4)

            let visible = bookHits.prefix(coord.visibleBooksCount)
            ForEach(Array(visible.enumerated()), id: \.element.bookIndex) { _, m in
                let b = library.books[m.bookIndex]
                BookRow(
                    book: b, library: library, indented: false,
                    coord: coord,
                    contextMenuBuilder: {
                        AnyView(
                            SearchExportMenu(checkedCount: coord.checkedBookLibids.count,
                                             isBusy: exportSession.isBusy, onExport: onRequestExport)
                        )
                    }
                )
            }
            if bookHits.count > coord.visibleBooksCount {
                Button("Загрузить ещё 20 книг") {
                    coord.visibleBooksCount += 20
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}
