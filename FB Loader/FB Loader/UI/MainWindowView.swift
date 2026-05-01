import SwiftUI
import AppKit

struct MainWindowView: View {
    let library: Library
    @Environment(AppState.self) private var state

    var body: some View {
        HSplitView {
            LeftSidebarView(library: library)
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
            VSplitView {
                BooksTableView(library: library)
                    .frame(minHeight: 200)
                if let libid = state.selectedBookLibid,
                   let book = library.books.first(where: { $0.libid == libid }),
                   let archives = state.userPaths.archivesDirectoryURL {
                    BookDetailView(library: library, archivesRoot: archives, book: book)
                        .frame(minHeight: 200)
                } else {
                    Text("Выберите книгу").foregroundStyle(.secondary).frame(minHeight: 200)
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .onChange(of: state.shouldStartExport) { _, newValue in
            guard newValue else { return }
            state.shouldStartExport = false
            runExport()
        }
        .sheet(item: Binding(
            get: { state.exportProgress.map { ProgressIdentifier(progress: $0) } },
            set: { _ in })) { wrapper in
                ExportProgressSheet(progress: wrapper.progress) {
                    state.exportProgress = nil
                }
        }
    }

    private struct ProgressIdentifier: Identifiable {
        let progress: ExportProgress
        var id: ObjectIdentifier { ObjectIdentifier(progress) }
    }

    private func runExport() {
        guard !state.checkedBookLibids.isEmpty,
              let archives = state.userPaths.archivesDirectoryURL else { return }
        // 1. Ask user for export folder, prefilled with last one or ~/Downloads.
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = state.userPaths.lastExportDirectoryURL
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        state.userPaths.lastExportDirectoryURL = folder

        // 2. Plan + run.
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
