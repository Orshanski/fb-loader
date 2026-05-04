import SwiftUI

struct BooksTableView: View {
    let library: Library
    @Environment(AppState.self) private var state

    private struct GroupedRow: Identifiable {
        struct BookEntry: Identifiable {
            let id: String
            let book: Book
        }

        enum Kind { case loose(Book); case seriesHeader(Series, [BookEntry]) }
        let id: String
        let kind: Kind
    }

    private var visibleBooks: [Book] {
        if let aid = state.selectedAuthorID, state.sidebarTab == .authors {
            return BooksByContext.books(for: .author(aid),
                                        language: state.languageFilter,
                                        in: library)
        }
        if let sid = state.selectedSeriesID, state.sidebarTab == .series {
            return BooksByContext.books(for: .series(sid),
                                        language: state.languageFilter,
                                        in: library)
        }
        if let gid = state.selectedGenreID, state.sidebarTab == .genres {
            return BooksByContext.books(for: .genre(gid),
                                        language: state.languageFilter,
                                        in: library)
        }
        return []
    }

    private var groups: [GroupedRow] {
        let books = visibleBooks
        var loose: [Book] = []
        var bySeries: [Int32: [Book]] = [:]
        for b in books {
            if let sid = b.seriesID { bySeries[sid, default: []].append(b) }
            else { loose.append(b) }
        }
        var rows: [GroupedRow] = loose.enumerated().map { offset, book in
            GroupedRow(id: "b-\(book.libid)-\(offset)", kind: .loose(book))
        }
        // O(1) series name lookup via the secondary index from Library.init.
        for (sectionOffset, entry) in bySeries.sorted(by: {
            (library.seriesByID[$0.key]?.name ?? "") < (library.seriesByID[$1.key]?.name ?? "")
        }).enumerated() {
            let (sid, items) = entry
            let s = library.seriesByID[sid] ?? Series(id: sid, name: "?")
            let sorted = items.sorted { ($0.seriesNum ?? Int16.max) < ($1.seriesNum ?? Int16.max) }
            let entries = sorted.enumerated().map { offset, book in
                GroupedRow.BookEntry(id: "sb-\(sid)-\(book.libid)-\(offset)", book: book)
            }
            rows.append(GroupedRow(id: "s-\(sid)-\(sectionOffset)", kind: .seriesHeader(s, entries)))
        }
        return rows
    }

    var body: some View {
        @Bindable var s = state
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(groups) { row in
                        switch row.kind {
                        case .loose(let b):
                            bookRow(for: b, indented: false, state: s)
                        case .seriesHeader(let series, let items):
                            seriesGroupHeader(series, count: items.count)
                            ForEach(items) { item in
                                bookRow(for: item.book, indented: true, state: s)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func bookRow(for b: Book, indented: Bool, state s: AppState) -> some View {
        BookRow(
            book: b,
            library: library,
            indented: indented,
            isChecked: Binding(
                get: { s.checkedBookLibids.contains(b.libid) },
                set: { isOn in
                    if isOn { s.checkedBookLibids.insert(b.libid) }
                    else    { s.checkedBookLibids.remove(b.libid) }
                }
            ),
            isSelected: Binding(
                get: { s.selectedBookLibid == b.libid },
                set: { newValue in if newValue { s.selectedBookLibid = b.libid } }
            ),
            contextMenuBuilder: {
                AnyView(
                    Button("Выгрузить отмеченные (\(s.checkedBookLibids.count))") {
                        // Export is kicked off by MainWindowView via the
                        // shouldStartExport flag on AppState.
                        s.shouldStartExport = true
                    }
                    .disabled(s.checkedBookLibids.isEmpty)
                )
            }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            breadcrumbRow
            colsRow
        }
        .padding(.horizontal, 16)
        .frame(height: 72)
    }

    @ViewBuilder
    private var breadcrumbRow: some View {
        let count = visibleBooks.count
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let label = breadcrumbLabel {
                Text(label.prefix).foregroundStyle(.secondary)
                Text(label.name).fontWeight(.semibold)
            } else {
                Text("Выберите автора, серию или жанр").foregroundStyle(.secondary)
            }
            Spacer()
            if count > 0 {
                Text(booksCountLabel(count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
    }

    private var breadcrumbLabel: (prefix: String, name: String)? {
        if state.sidebarTab == .authors,
           let aid = state.selectedAuthorID,
           let author = library.authorByID[aid] {
            return ("Книги автора", author.displayName)
        }
        if state.sidebarTab == .series,
           let sid = state.selectedSeriesID,
           let series = library.seriesByID[sid] {
            return ("Серия", series.name)
        }
        if state.sidebarTab == .genres,
           let gid = state.selectedGenreID,
           let genre = library.genreByID[gid] {
            return ("Жанр", genre.name)
        }
        return nil
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

    private var colsRow: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: BookRow.checkboxWidth)
            Text("Название")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("№")
                .frame(width: BookRow.numWidth, alignment: .trailing)
            Text("Размер")
                .frame(width: BookRow.sizeWidth, alignment: .trailing)
            Text("Дата")
                .frame(width: BookRow.dateWidth, alignment: .trailing)
            Text("Жанры")
                .frame(width: BookRow.genresWidth, alignment: .leading)
        }
        .font(.system(size: 10, weight: .semibold))
        .textCase(.uppercase)
        .kerning(0.6)
        .foregroundStyle(.secondary)
    }

    // MARK: - Series group header

    private func seriesGroupHeader(_ s: Series, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(s.name).font(.system(size: 13, weight: .semibold))
            Text("(\(count))").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - Language picker (used from MainWindow toolbar)

struct LanguageFilterLabel: View {
    var body: some View { Text("Язык книг") }
}

struct LanguageFilterPicker: View {
    let library: Library
    @Binding var selection: String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(displayLanguages(), id: \.self) { code in
                Text(label(for: code)).tag(code)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func displayLanguages() -> [String] {
        var langs = library.languages
        // Replace empty string with our sentinel for the picker.
        langs.removeAll { $0.isEmpty }
        if library.languages.contains("") {
            langs.append(BooksByContext.unspecifiedLanguageToken)
        }
        return langs
    }

    private func label(for code: String) -> String {
        if code == BooksByContext.unspecifiedLanguageToken { return "Не указан" }
        return code.uppercased()
    }
}
