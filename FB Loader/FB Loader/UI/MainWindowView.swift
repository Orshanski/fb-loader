import SwiftUI
import AppKit

struct MainWindowView: View {
    let library: Library
    @Environment(AppState.self) private var state

    var body: some View {
        // NavigationSplitView gives a proper macOS three-pane proportion that
        // HSplitView+nested-frame can't reliably enforce on macOS 26 — the old
        // layout let the authors list eat 2/3 of the window and squeezed the
        // books pane down to character-width wrapping.
        NavigationSplitView {
            LeftSidebarView(library: library)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
        } detail: {
            VSplitView {
                BooksTableView(library: library)
                    .frame(maxWidth: .infinity, minHeight: 200)
                if let libid = state.selectedBookLibid,
                   let book = library.bookByLibid[libid],
                   let archives = state.userPaths.archivesDirectoryURL {
                    BookDetailView(library: library, archivesRoot: archives, book: book)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    Text("Выберите книгу")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .frame(minHeight: 200)
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
