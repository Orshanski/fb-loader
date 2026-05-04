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
                   let book = library.bookByLibid[libid],
                   let archives = state.userPaths.archivesDirectoryURL {
                    BookDetailView(
                        library: library, archivesRoot: archives, book: book,
                        isCurrentSelection: { state.selectedBookLibid == book.libid },
                        onSelectAuthor: { aid in
                            state.sidebarTab = .authors
                            state.selectedAuthorID = aid
                            state.selectedSeriesID = nil
                            state.selectedGenreID = nil
                        },
                        onSelectSeries: { sid in
                            state.sidebarTab = .series
                            state.selectedSeriesID = sid
                            state.selectedAuthorID = nil
                            state.selectedGenreID = nil
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
        .onChange(of: state.shouldStartExport) { _, newValue in
            guard newValue else { return }
            state.shouldStartExport = false
            Task { await runExport() }
        }
        .sheet(item: Binding(
            get: { state.exportProgress.map { ProgressIdentifier(progress: $0) } },
            set: { _ in /* read-only binding; sheet dismissal is handled by ExportProgressSheet's done-closure below */ })) { wrapper in
                ExportProgressSheet(progress: wrapper.progress) {
                    state.exportProgress = nil
                }
        }
    }

    private struct ProgressIdentifier: Identifiable {
        let progress: ExportProgress
        var id: ObjectIdentifier { ObjectIdentifier(progress) }
    }

    private func runExport() async {
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

        let items = ExportPlanner.plan(
            libids: state.checkedBookLibids,
            rootFolder: folder,
            selectedAuthorID: state.sidebarTab == .authors ? state.selectedAuthorID : nil,
            selectedSeriesID: state.sidebarTab == .series ? state.selectedSeriesID : nil,
            in: library)
        let progress = ExportProgress()
        state.exportProgress = progress
        Task {
            await ExportRunner.run(items: items, archivesRoot: archives,
                                   library: library, progress: progress)
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
