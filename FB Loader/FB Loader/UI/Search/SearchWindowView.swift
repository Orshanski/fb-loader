import AppKit
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
    @State private var exportProgress: ExportProgress? = nil

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
            footerBar
            Divider()
            detailPanel
        }
        .frame(minWidth: 1000, minHeight: 700)
        .task(id: pendingSearchToken) {
            guard pendingSearchToken != nil else { return }
            await coord.runSearch(in: library)
        }
        .sheet(item: Binding(
            get: { exportProgress.map { ProgressIdentifier(progress: $0) } },
            set: { _ in })) { wrapper in
            ExportProgressSheet(progress: wrapper.progress) { exportProgress = nil }
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

    @ViewBuilder
    private var footerBar: some View {
        HStack {
            if !coord.checkedBookLibids.isEmpty {
                Text("Отмечено: \(coord.checkedBookLibids.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Экспорт отмеченных") { Task { await runExport() } }
                .disabled(coord.checkedBookLibids.isEmpty || archivesRoot == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
    }

    private func triggerSearch() {
        pendingSearchToken = UUID()
    }

    @MainActor
    private func runExport() async {
        guard !coord.checkedBookLibids.isEmpty,
              let archives = archivesRoot else { return }
        let userPaths = UserPaths.shared
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        // Pre-fill последней папкой экспорта, как в MainWindowView.runExport.
        panel.directoryURL = userPaths.lastExportDirectoryURL
            ?? FileManager.default.urls(for: .downloadsDirectory,
                                        in: .userDomainMask).first
        guard let folder = await panel.selectedDirectory() else { return }
        userPaths.lastExportDirectoryURL = folder

        let items = ExportPlanner.plan(
            libids: coord.checkedBookLibids,
            rootFolder: folder,
            selectedAuthorID: nil,
            selectedSeriesID: nil,
            in: library
        )
        let progress = ExportProgress()
        exportProgress = progress
        Task {
            await ExportRunner.run(items: items, archivesRoot: archives,
                                   library: library, progress: progress)
        }
    }
}

private struct ProgressIdentifier: Identifiable {
    let progress: ExportProgress
    var id: ObjectIdentifier { ObjectIdentifier(progress) }
}

private extension NSOpenPanel {
    @MainActor
    func selectedDirectory() async -> URL? {
        await withCheckedContinuation { c in
            begin { r in c.resume(returning: r == .OK ? self.url : nil) }
        }
    }
}
