import Foundation

/// Диапазон дат добавления книги, включительно с обоих концов.
/// Отсутствие фильтра — это `nil` у `AppState.dateFilter`, а не пустые
/// границы: здесь обе границы всегда заданы.
nonisolated struct DateRangeFilter: Equatable, Sendable {
    let from: Date
    let to: Date

    func contains(_ book: Book) -> Bool {
        guard let d = book.dateAdded else { return false }
        return d >= from && d <= to
    }

    /// «01.03.2013 — 30.06.2015» для шапки таблицы.
    var label: String {
        "\(DateFormat.dayMonthYear.string(from: from)) — \(DateFormat.dayMonthYear.string(from: to))"
    }
}

/// Единственный форматтер даты в приложении. `DateFormatter` дорог в
/// создании, а строится он на каждую видимую строку таблицы.
nonisolated enum DateFormat {
    static let dayMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()
}
