import SwiftUI
import AppKit

struct LeftSidebarView: View {
    let library: Library
    @Environment(AppState.self) private var state
    @State private var showSearch = false

    var body: some View {
        @Bindable var s = state
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Picker("", selection: $s.sidebarTab) {
                        Text("Авторы").tag(AppState.SidebarTab.authors)
                        Text("Серии").tag(AppState.SidebarTab.series)
                        Text("Жанры").tag(AppState.SidebarTab.genres)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    LanguageFilterPicker(library: library, selection: $s.languageFilter)

                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Поиск по библиотеке")
                }

                TextField("Фильтр", text: $s.sidebarFilter)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 12)
            .frame(height: 72)

            Divider()

            // Top breathing room so the first row doesn't press against the divider.
            Color.clear.frame(height: 4)

            switch s.sidebarTab {
            case .authors:
                AuthorsListView(library: library,
                                filterText: s.sidebarFilter,
                                languageFilter: s.languageFilter,
                                selectedAuthorID: $s.selectedAuthorID)
            case .series:
                SeriesListView(library: library,
                               filterText: s.sidebarFilter,
                               languageFilter: s.languageFilter,
                               selectedSeriesID: $s.selectedSeriesID)
            case .genres:
                GenresListView(library: library,
                               filterText: s.sidebarFilter,
                               languageFilter: s.languageFilter,
                               selectedGenreID: $s.selectedGenreID)
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchWindowView(
                library: library,
                archivesRoot: state.userPaths.archivesDirectoryURL,
                initialLanguage: state.languageFilter,
                preferredSize: searchSheetSize(),
                onClose: { showSearch = false }
            )
        }
    }

    /// 80% of main window — 10% margin on each side. Read at sheet-open
    /// time. If main window is unavailable for some reason (rare —
    /// sidebar lives inside main window), falls back to a sensible default.
    private func searchSheetSize() -> CGSize {
        if let main = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && !$0.isSheet }) {
            let parent = main.frame.size
            return CGSize(width: parent.width * 0.8,
                          height: parent.height * 0.8)
        }
        return CGSize(width: 1100, height: 800)
    }
}
