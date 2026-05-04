import SwiftUI

struct SearchWindowView: View {
    let library: Library
    let archivesRoot: URL?
    /// Initial language inherited from main window at sheet-open time.
    let initialLanguage: String
    /// Closure to dismiss the sheet — provided by the parent (LeftSidebarView).
    let onClose: () -> Void

    @State private var coord: SearchCoordinator
    /// Search trigger token for SwiftUI `.task(id:)` — flipping it kicks
    /// off a search. Initial nil → no search until the user clicks «Поиск».
    @State private var pendingSearchToken: UUID? = nil

    init(library: Library, archivesRoot: URL?, initialLanguage: String,
         onClose: @escaping () -> Void) {
        self.library = library
        self.archivesRoot = archivesRoot
        self.initialLanguage = initialLanguage
        self.onClose = onClose
        _coord = State(initialValue: SearchCoordinator(initialLanguage: initialLanguage))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            content
            Divider()
            detailPanel
        }
        .frame(minWidth: 1000, minHeight: 700)
        .task(id: pendingSearchToken) {
            guard pendingSearchToken != nil else { return }
            await coord.runSearch(in: library)
        }
    }

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 10) {
            TextField("Запрос…", text: $coord.query)
                .textFieldStyle(.roundedBorder)
                .disabled(coord.isSearching)
                .onSubmit { triggerSearch() }
                .frame(maxWidth: .infinity)

            LanguageFilterPicker(library: library, selection: $coord.languageFilter)
                .disabled(coord.isSearching)

            Button(coord.isSearching ? "Поиск…" : "Поиск") {
                triggerSearch()
            }
            .disabled(coord.isSearching || coord.query.trimmingCharacters(in: .whitespaces).isEmpty)
            // Enter в TextField обрабатывается через `.onSubmit { triggerSearch() }`
            // на самом поле — этого достаточно. `.keyboardShortcut(.return)` на
            // кнопке тут добавлять не надо: SwiftUI на macOS отдаёт Enter
            // фокусированному TextField через onSubmit, а второй обработчик на
            // кнопке создаст конкуренцию (двойной запуск или пропуск, по
            // настроению фокуса).

            Button("Закрыть") { onClose() }
                .keyboardShortcut(.cancelAction)   // Escape
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if coord.isSearching {
            VStack(spacing: 12) {
                ProgressView()
                Text("Ищем…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let r = coord.results {
            if r.authors.isEmpty && r.series.isEmpty && r.books.isEmpty {
                Text("По запросу «\(coord.lastQuery)» ничего не найдено")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                SearchResultListView(coord: coord, library: library, results: r)
            }
        } else {
            Text("Введите запрос и нажмите «Поиск»")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let libid = coord.selectedBookLibid,
           let book = library.bookByLibid[libid],
           let archives = archivesRoot {
            BookDetailView(library: library, archivesRoot: archives, book: book)
                .frame(maxWidth: .infinity, minHeight: 380, idealHeight: 420)
        } else {
            Text("Выберите книгу")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: 380, idealHeight: 420)
        }
    }

    private func triggerSearch() {
        pendingSearchToken = UUID()
    }
}

// MARK: - Transient stub
//
// Replaced (and moved to its own file) by Task 11. Kept here only so the
// build stays green between tasks.

struct SearchResultListView: View {
    let coord: SearchCoordinator
    let library: Library
    let results: SearchResults

    var body: some View {
        Text("Список результатов — раздел реализуется в Task 11")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
