import SwiftUI

struct MainWindowView: View {
    let library: Library
    @Environment(AppState.self) private var state
    var body: some View {
        Text("Library loaded: \(library.books.count) books")
            .frame(minWidth: 1000, minHeight: 600)
    }
}
