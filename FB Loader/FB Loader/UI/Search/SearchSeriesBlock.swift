import SwiftUI

/// One «серия <имя>» result block. Header includes a right-side
/// subtitle with the series's «основной» author + book count
/// (per spec § Серии). Header click toggles collapse.
struct SearchSeriesBlock: View {
    @Bindable var coord: SearchCoordinator
    let library: Library
    let seriesIndex: Int
    let onRequestExport: () -> Void

    private let defaultBooksLimit = 5

    private var series: Series { library.series[seriesIndex] }
    private var collapsed: Bool { coord.collapsedSeries.contains(seriesIndex) }
    private var fullyExpanded: Bool { coord.fullyExpandedSeries.contains(seriesIndex) }

    /// Books of the series in current language, sorted by `seriesNum`.
    /// Computed once and shared between header (count + primary author)
    /// and body (rows).
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
        return library.authorByID[aid]
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
            // Spec § Серии: «Справа от заголовка — короткая контекстная
            // строка (имя «основного» автора серии + счётчик «N книг»)».
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

    private func booksCountLabel(_ n: Int) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        let word: String
        if mod100 >= 11 && mod100 <= 14 { word = "книг" }
        else if mod10 == 1 { word = "книга" }
        else if mod10 >= 2 && mod10 <= 4 { word = "книги" }
        else { word = "книг" }
        return "\(n) \(word)"
    }

    @ViewBuilder
    private var booksList: some View {
        let allBooks = booksInLanguage
        let visibleBooks = fullyExpanded ? allBooks : Array(allBooks.prefix(defaultBooksLimit))
        ForEach(visibleBooks, id: \.libid) { b in
            BookRow(
                book: b, library: library, indented: true,
                isChecked: bindingChecked(b),
                isSelected: bindingSelected(b),
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

    private func exportContextMenu() -> AnyView {
        AnyView(
            Button("Выгрузить отмеченные (\(coord.checkedBookLibids.count))") {
                onRequestExport()
            }
            .disabled(coord.checkedBookLibids.isEmpty)
        )
    }
}
