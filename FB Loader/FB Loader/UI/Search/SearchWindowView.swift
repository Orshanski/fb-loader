import AppKit
import SwiftUI

struct SearchWindowView: View {
    let library: Library
    let archivesRoot: URL?
    let exportSession: ExportSession
    /// Initial language inherited from main window at sheet-open time.
    let initialLanguage: String
    /// Closure to dismiss the sheet — provided by the parent (MainWindowView).
    let onClose: () -> Void
    /// Preferred sheet size — рассчитывается родителем как 80% от главного
    /// окна (10% полей с каждой стороны). Параметром, чтобы не лезть в
    /// `NSApp.mainWindow` из контента sheet'а, который сам не знает, кто
    /// его родитель.
    let preferredSize: CGSize

    @State private var coord: SearchCoordinator
    /// Search trigger token for SwiftUI `.task(id:)` — flipping it kicks
    /// off a search. Initial nil → no search until the user clicks «Поиск».
    @State private var pendingSearchToken: UUID? = nil

    init(library: Library, archivesRoot: URL?, exportSession: ExportSession, initialLanguage: String,
         preferredSize: CGSize,
         onClose: @escaping () -> Void) {
        self.library = library
        self.archivesRoot = archivesRoot
        self.exportSession = exportSession
        self.initialLanguage = initialLanguage
        self.preferredSize = preferredSize
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
        // Фиксированный размер sheet'а на основе размера главного окна
        // (80% — родитель в MainWindowView читает NSApp.mainWindow и
        // считает .width * 0.8 / .height * 0.8). Фиксированный (не min/max)
        // фрейм убирает AppKit-recursion warning во время первого layout
        // pass'а sheet'а.
        .frame(width: preferredSize.width, height: preferredSize.height)
        .task(id: pendingSearchToken) {
            guard pendingSearchToken != nil else { return }
            await coord.runSearch(in: library)
        }
        .sheet(item: Binding(
            get: { exportSession.progress(for: .search) },
            set: { _ in })) { progress in
            ExportProgressSheet(progress: progress) { exportSession.closeProgress(origin: .search) }
        }
        // Страховка от устаревшего итога при следующем открытии поиска.
        .onDisappear { exportSession.closeProgress(origin: .search) }
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
                SearchResultListView(
                    coord: coord, library: library, results: r, exportSession: exportSession,
                    onRequestExport: { Task { await startExport() } }
                )
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
           let book = library.book(libid: libid),
           let archives = archivesRoot {
            BookDetailView(
                library: library, archivesRoot: archives, book: book,
                isCurrentSelection: { coord.selectedBookLibid == book.libid },
                onSelectAuthor: { _ in
                    // No-op for v1 in sheet context — sidebar navigation
                    // doesn't apply when viewing a book in the search sheet.
                },
                onSelectSeries: { _ in
                    // No-op for v1 in sheet context.
                }
            )
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

    @MainActor
    private func startExport() async {
        let coord = coord
        await exportSession.start(ExportRequest(
            libids: coord.checkedBookLibids, library: library,
            selectedAuthorID: nil, selectedSeriesID: nil,
            format: .fb2, origin: .search,
            uncheck: { _ = coord.checkedBookLibids.remove($0) }))
    }
}
