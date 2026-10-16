import Foundation

nonisolated enum BookGrouping {
    struct SeriesGroup: Sendable {
        let series: Series
        let books: [Book]
    }

    /// Серии по имени (при равенстве — по id), книги серии по номеру; ничья и книги без номера — в порядке выборки.
    static func group(_ books: [Book], library: Library) -> (loose: [Book], series: [SeriesGroup]) {
        var loose: [Book] = []
        var bySeries: [Int32: [(offset: Int, book: Book)]] = [:]
        for (offset, b) in books.enumerated() {
            if let sid = b.seriesID { bySeries[sid, default: []].append((offset, b)) }
            else { loose.append(b) }
        }
        let groups = bySeries.keys
            .map { library.series(id: $0) ?? Series(id: $0, name: "?") }
            .sorted { $0.name != $1.name ? $0.name < $1.name : $0.id < $1.id }
            .map { s in
                let items = (bySeries[s.id] ?? []).sorted { a, b in
                    let na = a.book.seriesNum ?? .max
                    let nb = b.book.seriesNum ?? .max
                    return na != nb ? na < nb : a.offset < b.offset
                }
                return SeriesGroup(series: s, books: items.map(\.book))
            }
        return (loose, groups)
    }
}

/// Русское склонение: 1 книга, 2 книги, 5 книг (11–14 — всегда «много»).
nonisolated func russianPlural(_ n: Int, one: String, few: String, many: String) -> String {
    let mod10 = n % 10
    let mod100 = n % 100
    let word: String
    if mod100 >= 11 && mod100 <= 14 { word = many }
    else if mod10 == 1 { word = one }
    else if mod10 >= 2 && mod10 <= 4 { word = few }
    else { word = many }
    return "\(n) \(word)"
}

nonisolated func booksCountLabel(_ n: Int) -> String {
    russianPlural(n, one: "книга", few: "книги", many: "книг")
}
