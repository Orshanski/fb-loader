import SwiftUI

/// Ссылка, а не замыкание: замыкание создаётся заново на каждом проходе body
/// главного окна, и таблица книг пересчитывалась бы при каждом клике по книге.
final class ExportAction {
    var perform: () -> Void = {}
    var isAvailable: () -> Bool = { true }
}

struct BooksTableView: View {
    let library: Library
    let exportAction: ExportAction

    var body: some View {
        BooksTableContent(library: library, exportAction: exportAction)
    }
}

private struct BooksTableContent: View {
    let library: Library
    let exportAction: ExportAction
    @Environment(AppState.self) private var state

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

    var body: some View {
        // Выборка и строки — только здесь и только при смене контекста, языка,
        // фильтра дат: выбор и галочки body не читает, их читает updateNSView.
        let result = visibleBooks
        let rows = BookTableRows.build(books: result.books, library: library)
        let key = BooksTableKey(context: context, language: state.languageFilter, dates: state.dateFilter)
        VStack(spacing: 0) {
            titleRow(count: result.books.count, total: result.total)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 40, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
            BooksTableRepresentable(state: state, library: library, rows: rows, key: key,
                                    exportAction: exportAction)
        }
    }

    @ViewBuilder
    private func titleRow(count: Int, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Строка заголовка фиксированной высоты: длинное имя усекается, а не переносится.
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
