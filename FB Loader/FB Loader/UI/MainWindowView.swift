import SwiftUI

struct MainWindowView: View {
    let library: Library
    @Environment(AppState.self) private var state

    var body: some View {
        HSplitView {
            LeftSidebarView(library: library)
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
            Text("Books table goes here")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 600)
    }
}
