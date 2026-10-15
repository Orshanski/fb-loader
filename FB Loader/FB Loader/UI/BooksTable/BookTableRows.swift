import Foundation

nonisolated enum BookTableRow: Sendable {
    case book(Book, inSeries: Bool)
    case seriesHeader(Series, count: Int)
}

/// Строки таблицы книг главного окна: книги без серии, затем группы серий.
nonisolated struct BookTableRows: Sendable {
    let rows: [BookTableRow]
    private let rowByLibid: [Int32: Int]

    init(rows: [BookTableRow]) {
        self.rows = rows
        var index: [Int32: Int] = [:]
        index.reserveCapacity(rows.count)
        for (i, row) in rows.enumerated() {
            if case .book(let b, _) = row, index[b.libid] == nil { index[b.libid] = i }
        }
        rowByLibid = index
    }

    static let empty = BookTableRows(rows: [])

    var count: Int { rows.count }

    func row(ofLibid libid: Int32) -> Int? { rowByLibid[libid] }

    func book(at row: Int) -> Book? {
        guard rows.indices.contains(row), case .book(let b, _) = rows[row] else { return nil }
        return b
    }

    func isBook(_ row: Int) -> Bool { book(at: row) != nil }

    func libid(at row: Int) -> Int32? { book(at: row)?.libid }

    static func build(books: [Book], library: Library) -> BookTableRows {
        var result: [BookTableRow] = []
        result.reserveCapacity(books.count)
        var bySeries: [Int32: [(offset: Int, book: Book)]] = [:]
        for (offset, b) in books.enumerated() {
            if let sid = b.seriesID {
                bySeries[sid, default: []].append((offset, b))
            } else {
                result.append(.book(b, inSeries: false))
            }
        }
        let series = bySeries.keys
            .map { library.series(id: $0) ?? Series(id: $0, name: "?") }
            .sorted { $0.name != $1.name ? $0.name < $1.name : $0.id < $1.id }
        for s in series {
            let items = (bySeries[s.id] ?? []).sorted { a, b in
                let na = a.book.seriesNum ?? .max
                let nb = b.book.seriesNum ?? .max
                return na != nb ? na < nb : a.offset < b.offset
            }
            result.append(.seriesHeader(s, count: items.count))
            result.append(contentsOf: items.map { .book($0.book, inSeries: true) })
        }
        return BookTableRows(rows: result)
    }
}
