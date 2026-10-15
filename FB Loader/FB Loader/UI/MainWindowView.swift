import SwiftUI
import AppKit

struct MainWindowView: View {
    let library: Library
    @Environment(AppState.self) private var state
    @State private var sidebarVisible = true

    private let booksTableMinHeight: CGFloat = 240
    private let booksTableIdealHeight: CGFloat = 300
    private let bookDetailMinHeight: CGFloat = 380
    private let bookDetailIdealHeight: CGFloat = 400

    var body: some View {
        HSplitView {
            if sidebarVisible {
                LeftSidebarView(library: library)
                    .frame(minWidth: 280, idealWidth: 300, maxWidth: 480)
            }
            VSplitView {
                BooksTableView(library: library)
                    .frame(maxWidth: .infinity,
                           minHeight: booksTableMinHeight,
                           idealHeight: booksTableIdealHeight)
                if let libid = state.selectedBookLibid,
                   let book = library.book(libid: libid),
                   let archives = state.userPaths.archivesDirectoryURL {
                    BookDetailView(
                        library: library, archivesRoot: archives, book: book,
                        isCurrentSelection: { state.selectedBookLibid == book.libid },
                        onSelectAuthor: { aid in
                            let name = library.author(id: aid)?.displayName
                            state.selectAuthor(aid, deepLinkName: name)
                        },
                        onSelectSeries: { sid in
                            let name = library.series(id: sid)?.name
                            state.selectSeries(sid, deepLinkName: name)
                        }
                    )
                        .frame(maxWidth: .infinity,
                               minHeight: bookDetailMinHeight,
                               idealHeight: bookDetailIdealHeight)
                } else {
                    Text("Выберите книгу")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(minHeight: bookDetailMinHeight,
                               idealHeight: bookDetailIdealHeight)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 640)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    sidebarVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(sidebarVisible ? "Скрыть боковую панель" : "Показать боковую панель")
            }
        }
        // Таблица книг — ScrollView, а её содержимое macOS пускает под панель
        // окна: без непрозрачного фона строки просвечивают в полосе заголовка.
        .toolbarBackground(.visible, for: .windowToolbar)
        .onChange(of: state.shouldStartExport) { _, newValue in
            guard newValue else { return }
            state.shouldStartExport = false
            Task { await runExport() }
        }
        .sheet(item: Binding(
            get: { state.exportProgress.map { ProgressIdentifier(progress: $0) } },
            set: { _ in
                // Read-only binding — sheet dismissal is handled by
                // ExportProgressSheet's done-closure below.
            })) { wrapper in
                ExportProgressSheet(progress: wrapper.progress) {
                    state.exportProgress = nil
                }
        }
        .onExportProgress(state.exportProgress) { progress in
            state.checkedBookLibids = progress.removingSucceeded(
                from: state.checkedBookLibids)
        }
    }

    private struct ProgressIdentifier: Identifiable {
        let progress: ExportProgress
        var id: ObjectIdentifier { ObjectIdentifier(progress) }
    }

    private func runExport() async {
        // Гард против двойного запуска: если предыдущий ExportRunner ещё
        // не вернулся (sheet жив, либо last in-flight книга дописывается),
        // повторный клик «Выгрузить» игнорируется — иначе два Task'а
        // погонятся за общим state.checkedBookLibids.
        guard state.exportProgress == nil else { return }
        guard !state.checkedBookLibids.isEmpty,
              let archives = state.userPaths.archivesDirectoryURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = state.userPaths.lastExportDirectoryURL
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let folder = await panel.selectedDirectory() else { return }
        state.userPaths.lastExportDirectoryURL = folder

        let authorID: Int32?
        if case .authors(let id) = state.sidebar { authorID = id } else { authorID = nil }
        let seriesID: Int32?
        if case .series(let id) = state.sidebar { seriesID = id } else { seriesID = nil }
        let items = ExportPlanner.plan(
            libids: state.checkedBookLibids,
            rootFolder: folder,
            selectedAuthorID: authorID,
            selectedSeriesID: seriesID,
            in: library)
        let progress = ExportProgress()
        state.exportProgress = progress
        Task {
            await ExportRunner.run(items: items, exportRoot: folder, archivesRoot: archives,
                                   library: library, progress: progress)
            // Финальный пересчёт — страховка от любого пути, при котором
            // последний `.onChange` не был доставлен или потерял
            // `state.exportProgress`: пользователь закрыл sheet после
            // «Отмена», SwiftUI переставил порядок диспатчей, runner
            // дописал последнюю книгу после обнуления биндинга и т.п.
            // Здесь берём полное `progress.succeeded` с захваченного
            // объекта и снимаем оставшееся.
            state.checkedBookLibids = progress.removingSucceeded(
                from: state.checkedBookLibids)
        }
    }
}

private extension NSOpenPanel {
    @MainActor
    func selectedDirectory() async -> URL? {
        await withCheckedContinuation { continuation in
            begin { response in
                continuation.resume(returning: response == .OK ? self.url : nil)
            }
        }
    }
}
