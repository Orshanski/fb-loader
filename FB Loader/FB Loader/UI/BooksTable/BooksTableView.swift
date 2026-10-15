import SwiftUI

struct BooksTableView: View {
    let library: Library
    @Environment(AppState.self) private var state
    @State private var showDateFilter = false
    @State private var columns: BookTableColumns = .standard

    private struct GroupedRow: Identifiable {
        struct BookEntry: Identifiable {
            let id: String
            let book: Book
        }

        enum Kind { case loose(Book); case seriesHeader(Series, [BookEntry]) }
        let id: String
        let kind: Kind
    }

    private var context: BooksByContext.Context? {
        switch state.sidebar {
        case .authors(let id?): return .author(id)
        case .series(let id?):  return .series(id)
        case .genres(let id?):  return .genre(id)
        case .authors, .series, .genres: return nil
        }
    }

    private var visibleBooks: (books: [Book], total: Int) {
        guard let context else { return ([], 0) }
        return BooksByContext.booksWithTotal(for: context,
                                             language: state.languageFilter,
                                             dates: state.dateFilter,
                                             in: library)
    }

    private func groups(from books: [Book]) -> [GroupedRow] {
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
            (library.series(id: $0.key)?.name ?? "") < (library.series(id: $1.key)?.name ?? "")
        }).enumerated() {
            let (sid, items) = entry
            let s = library.series(id: sid) ?? Series(id: sid, name: "?")
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
        // Считается один раз за проход body: и счётчик в шапке, и список
        // берут отсюда — раньше тот же фильтр выполнялся дважды.
        let result = visibleBooks
        // Шапка живёт ВНУТРИ ScrollView закреплённой секцией. Снаружи она
        // была шире строк ровно на ширину полосы прокрутки, и подписи
        // колонок стояли правее своих значений.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(groups(from: result.books)) { row in
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
                } header: {
                    VStack(spacing: 0) {
                        header(count: result.books.count, total: result.total)
                        Divider()
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
            .padding(.bottom, 4)
        }
        .onGeometryChange(for: BookTableColumns.self) { proxy in
            BookTableColumns.visibleColumns(forWidth: proxy.size.width)
        } action: { columns = $0 }
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
            },
            columns: columns
        )
    }

    // MARK: - Header

    private func header(count: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(count: count, total: total)
            colsRow
        }
        .padding(.horizontal, 16)
        .frame(height: 72)
    }

    @ViewBuilder
    private func titleRow(count: Int, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Шапка фиксированной высоты 72pt: вторая строка названия обрезала
            // бы подписи колонок, поэтому длинное имя усекается.
            if let label = titleLabel {
                Text(label.prefix).foregroundStyle(.secondary)
                    .fixedSize()
                Text(label.name).fontWeight(.semibold)
                    .truncationMode(.tail)
            } else {
                Text("Выберите автора, серию или жанр").foregroundStyle(.secondary)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            counter(count: count, total: total)
                .fixedSize()
        }
        .lineLimit(1)
        .font(.system(size: 13))
    }

    @ViewBuilder
    private func counter(count: Int, total: Int) -> some View {
        if let filter = state.dateFilter {
            HStack(spacing: 6) {
                // Без склонения и всегда видимо, включая «0 из 264»: иначе у
                // пустой таблицы пропадает единственное объяснение, почему
                // она пуста.
                Text("\(count) из \(total)")
                Text("·").foregroundStyle(.tertiary)
                Text(filter.label)
                Button {
                    state.applyDateFilter(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Снять фильтр по дате")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if count > 0 {
            Text(booksCountLabel(count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var titleLabel: (prefix: String, name: String)? {
        switch state.sidebar {
        case .authors(let id?):
            guard let author = library.author(id: id) else { return nil }
            return ("Книги автора", author.displayName)
        case .series(let id?):
            guard let series = library.series(id: id) else { return nil }
            return ("Серия", series.name)
        case .genres(let id?):
            guard let genre = library.genreByID[id] else { return nil }
            return ("Жанр", genre.name)
        case .authors, .series, .genres:
            return nil
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

    private var colsRow: some View {
        HStack(spacing: BookTableColumns.spacing) {
            Spacer().frame(width: BookTableColumns.checkboxWidth)
            Text("Название")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("№")
                .frame(width: BookTableColumns.numWidth, alignment: .trailing)
            if columns.showsSize {
                Text("Размер")
                    .frame(width: BookTableColumns.sizeWidth, alignment: .trailing)
            }
            dateColumnButton
            if columns.showsGenres {
                Text("Жанры")
                    .frame(width: columns.genresWidth, alignment: .leading)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .textCase(.uppercase)
        .kerning(0.6)
        .foregroundStyle(.secondary)
    }

    /// Заголовок колонки «Дата» — кнопка, открывающая поповер фильтра.
    /// Занимает ровно `BookTableColumns.dateWidth` и ровно тем же `Text`, что и
    /// остальные заголовки: любой значок внутри этой ширины сдвинул бы
    /// подпись относительно значений в строках. Кликабельность показывается
    /// подсветкой при наведении, а активный фильтр — цветом.
    private var dateColumnButton: some View {
        Button {
            showDateFilter = true
        } label: {
            // Правый край колонки держит шеврон, а подпись стоит левее — как
            // индикатор сортировки в Finder. Требовать, чтобы слово «Дата»
            // само упиралось в край, незачем.
            HStack(spacing: 3) {
                Text("Дата")
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .frame(width: BookTableColumns.dateWidth, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(state.dateFilter == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        .disabled(context == nil)
        .popover(isPresented: $showDateFilter, arrowEdge: .bottom) {
            DateFilterPopover(current: state.dateFilter) { next in
                state.applyDateFilter(next)
                showDateFilter = false
            }
        }
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
