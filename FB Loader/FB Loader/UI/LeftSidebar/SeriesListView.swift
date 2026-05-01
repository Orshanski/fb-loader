import SwiftUI

struct SeriesListView: View {
    let library: Library
    let filterText: String
    @Binding var selectedSeriesID: Int32?

    private var visibleSeries: [Series] {
        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        if needle.isEmpty { return library.series }
        // Precomputed lowercased names: see AuthorsListView for the rationale.
        var result: [Series] = []
        result.reserveCapacity(64)
        for i in library.series.indices
        where library.lowercasedSeriesNames[i].contains(needle) {
            result.append(library.series[i])
        }
        return result
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
