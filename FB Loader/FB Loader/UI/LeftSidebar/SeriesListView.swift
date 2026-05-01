import SwiftUI

struct SeriesListView: View {
    let library: Library
    let filterText: String
    @Binding var selectedSeriesID: Int32?

    private var visibleSeries: [Series] {
        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        if needle.isEmpty { return library.series }
        return library.series.filter { $0.name.lowercased().contains(needle) }
    }

    var body: some View {
        List(selection: $selectedSeriesID) {
            ForEach(visibleSeries) { s in
                let count = library.bookCountBySeries[s.id, default: 0]
                Text("\(s.name) (\(count))")
                    .tag(Int32?.some(s.id))
            }
        }
    }
}
