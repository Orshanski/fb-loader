import SwiftUI

struct LeftSidebarView: View {
    let library: Library
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var s = state
        VStack(spacing: 0) {
            Picker("", selection: $s.sidebarTab) {
                Text("Авторы").tag(AppState.SidebarTab.authors)
                Text("Серии").tag(AppState.SidebarTab.series)
            }
            .pickerStyle(.segmented)
            .padding(8)

            TextField("Фильтр", text: $s.sidebarFilter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)

            switch s.sidebarTab {
            case .authors:
                AuthorsListView(library: library,
                                filterText: s.sidebarFilter,
                                selectedAuthorID: $s.selectedAuthorID)
            case .series:
                SeriesListView(library: library,
                               filterText: s.sidebarFilter,
                               selectedSeriesID: $s.selectedSeriesID)
            }
        }
    }
}
