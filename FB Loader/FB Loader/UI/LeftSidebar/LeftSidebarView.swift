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
                    Picker("", selection: pickerBinding) {
                        Text("Авторы").tag(SectionTag.authors)
                        Text("Серии").tag(SectionTag.series)
                        Text("Жанры").tag(SectionTag.genres)
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

            switch state.sidebar {
            case .authors(let id):
                AuthorsListView(library: library,
                                filterText: s.sidebarFilter,
                                languageFilter: s.languageFilter,
                                selectedAuthorID: authorBinding(currentID: id))
            case .series(let id):
                SeriesListView(library: library,
                               filterText: s.sidebarFilter,
                               languageFilter: s.languageFilter,
                               selectedSeriesID: seriesBinding(currentID: id))
            case .genres(let id):
                GenresListView(library: library,
                               filterText: s.sidebarFilter,
                               languageFilter: s.languageFilter,
                               selectedGenreID: genreBinding(currentID: id))
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

    private enum SectionTag: Hashable { case authors, series, genres }

    private var pickerBinding: Binding<SectionTag> {
        Binding(
            get: {
                switch state.sidebar {
                case .authors: return .authors
                case .series:  return .series
                case .genres:  return .genres
                }
            },
            set: { newTag in
                switch newTag {
                case .authors: state.selectSection(.authors(nil))
                case .series:  state.selectSection(.series(nil))
                case .genres:  state.selectSection(.genres(nil))
                }
            }
        )
    }

    private func authorBinding(currentID: Int32?) -> Binding<Int32?> {
        Binding(get: { currentID }, set: { state.selectAuthor($0) })
    }

    private func seriesBinding(currentID: Int32?) -> Binding<Int32?> {
        Binding(get: { currentID }, set: { state.selectSeries($0) })
    }

    private func genreBinding(currentID: Int16?) -> Binding<Int16?> {
        Binding(get: { currentID }, set: { state.selectGenre($0) })
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
