import SwiftUI

struct SeriesListView: View {
    let library: Library
    let filterText: String
    @Binding var selectedSeriesID: Int32?

    @State private var filtered: [Series] = []

    var body: some View {
        LazyListTable(items: filtered, selectedID: $selectedSeriesID) { s in
            let count = library.bookCountBySeries[s.id, default: 0]
            return "\(s.name) (\(count))"
        }
        .task(id: filterText) { await reloadFilter() }
    }

    /// Same off-main + 150 ms debounce as AuthorsListView.
    private func reloadFilter() async {
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }

        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        let lib = library
        let result: [Series] = await Task.detached(priority: .userInitiated) {
            if needle.isEmpty { return lib.series }
            var out: [Series] = []
            out.reserveCapacity(64)
            for i in lib.series.indices
            where lib.lowercasedSeriesNames[i].contains(needle) {
                out.append(lib.series[i])
            }
            return out
        }.value
        if Task.isCancelled { return }
        filtered = result
    }
}
