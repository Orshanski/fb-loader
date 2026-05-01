import SwiftUI

struct LeftSidebarView: View {
    let library: Library
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var s = state
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Picker("", selection: $s.sidebarTab) {
                        Text("Авторы").tag(AppState.SidebarTab.authors)
                        Text("Серии").tag(AppState.SidebarTab.series)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    LanguageFilterPicker(library: library)
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
            }
        }
    }
}
