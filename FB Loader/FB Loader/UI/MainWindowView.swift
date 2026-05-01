import SwiftUI

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
                Text("Book detail goes here")    // placeholder
                    .frame(minHeight: 200)
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
    }
}
