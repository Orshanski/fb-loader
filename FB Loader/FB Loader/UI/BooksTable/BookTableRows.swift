import Foundation

nonisolated enum BookTableRow: Sendable {
    case book(Book, inSeries: Bool)
    case seriesHeader(Series, count: Int)
}

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

    /// Без привязки значения: вызывается из `heightOfRow` на каждую строку и не должен копировать `Book`.
    func isBook(_ row: Int) -> Bool {
        guard rows.indices.contains(row), case .book = rows[row] else { return false }
        return true
    }

    func libid(at row: Int) -> Int32? { book(at: row)?.libid }

    static func build(books: [Book], library: Library) -> BookTableRows {
        let (loose, groups) = BookGrouping.group(books, library: library)
        var result: [BookTableRow] = []
        result.reserveCapacity(books.count + groups.count)
        result.append(contentsOf: loose.map { .book($0, inSeries: false) })
        for g in groups {
            result.append(.seriesHeader(g.series, count: g.books.count))
            result.append(contentsOf: g.books.map { .book($0, inSeries: true) })
        }
        return BookTableRows(rows: result)
    }
}

nonisolated extension BookTableRows {
    /// Заголовок серии не выбирается: клавиатура перескакивает его по
    /// направлению движения, мышь оставляет прежний выбор.
    func resolveSelection(proposed: Int?, current: Int?, byKeyboard: Bool) -> Int? {
        guard let p = proposed, rows.indices.contains(p) else { return current }
        if isBook(p) { return p }
        guard byKeyboard else { return current }
        let downward = current.map { p > $0 } ?? true
        if downward {
            return (p + 1 ..< rows.count).first(where: isBook) ?? current
        }
        return (0 ..< p).reversed().first(where: isBook) ?? current
    }

    enum ScrollTarget: Equatable, Sendable {
        case top
        case row(Int, header: Int?)
    }

    func scrollTarget(selectedLibid: Int32?) -> ScrollTarget {
        guard let libid = selectedLibid, let r = row(ofLibid: libid) else { return .top }
        let header = r > 0 && !isBook(r - 1) ? r - 1 : nil
        return .row(r, header: header)
    }
}

/// Выделение поставлено не пользователем (карточка автора/серии, переход из поиска): к книге надо прокрутить.
nonisolated func selectionChangedExternally(currentRow: Int, targetRow: Int?) -> Bool {
    guard let targetRow else { return false }
    return currentRow != targetRow
}

nonisolated enum SpaceRoute: Equatable, Sendable {
    case toggleCheck, typeSelect
}

/// Пробел внутри набора type-select («Война и мир») — часть поиска, а не галочка.
nonisolated func spaceRoute(lastTypeSelectKey: Date?, now: Date) -> SpaceRoute {
    guard let last = lastTypeSelectKey else { return .toggleCheck }
    return now.timeIntervalSince(last) < 1 ? .typeSelect : .toggleCheck
}

/// Клик и галочка ключ не меняют: по нему решается, пересобирать ли строки таблицы.
nonisolated struct BooksTableKey: Equatable, Sendable {
    let context: BooksByContext.Context?
    let language: String
    let dates: DateRangeFilter?
}
