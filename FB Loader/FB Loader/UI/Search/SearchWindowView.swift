import AppKit
import SwiftUI

struct SearchWindowView: View {
    let library: Library
    let archivesRoot: URL?
    let exportSession: ExportSession
    let initialLanguage: String
    let onClose: () -> Void
    let onOpenAuthor: (Int32, Book) -> Void
    let onOpenSeries: (Int32, Book) -> Void
    /// 80% главного окна; параметром, а не через `NSApp.mainWindow`: контент sheet'а не знает своего родителя.
    let preferredSize: CGSize

    @State private var coord: SearchCoordinator
    /// Смена значения запускает поиск через `.task(id:)`; nil — пока не нажали «Поиск».
    @State private var pendingSearchToken: UUID? = nil

    init(library: Library, archivesRoot: URL?, exportSession: ExportSession, initialLanguage: String,
         preferredSize: CGSize,
         onClose: @escaping () -> Void,
         onOpenAuthor: @escaping (Int32, Book) -> Void,
         onOpenSeries: @escaping (Int32, Book) -> Void) {
        self.library = library
        self.archivesRoot = archivesRoot
        self.exportSession = exportSession
        self.initialLanguage = initialLanguage
        self.preferredSize = preferredSize
        self.onClose = onClose
        self.onOpenAuthor = onOpenAuthor
        self.onOpenSeries = onOpenSeries
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
        // Фиксированный (не min/max) фрейм: иначе AppKit-recursion warning на первом layout pass'е sheet'а.
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
            // Enter обрабатывает `.onSubmit` на поле; `.keyboardShortcut(.return)` на кнопке дал бы второй
            // обработчик (двойной запуск или пропуск).

            Button("Закрыть") { onClose() }
                .keyboardShortcut(.cancelAction)
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
                onSelectAuthor: { aid in onOpenAuthor(aid, book) },
                onSelectSeries: { sid in onOpenSeries(sid, book) }
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
