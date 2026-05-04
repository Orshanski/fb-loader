import Foundation

/// Один матч-автор: индекс в `Library.authors` + скор.
/// Скор — `Double` 0..100, отсечка по `FuzzyScorer.scoreCutoff` уже
/// применена при формировании результата, в выдачу попадают только
/// matches >= cutoff.
nonisolated struct AuthorMatch: Sendable, Equatable {
    let authorIndex: Int
    let score: Double
}

/// Один матч-серия.
nonisolated struct SeriesMatch: Sendable, Equatable {
    let seriesIndex: Int
    let score: Double
}

/// Один матч-книга.
nonisolated struct BookMatch: Sendable, Equatable {
    let bookIndex: Int
    let score: Double
}

/// Полный результат одного запроса. Каждый бакет уже отсортирован по
/// убыванию скорера. Для author/series — все matches выше cutoff
/// (UI ограничивает топ-10 + «Показать всех»). Для books — все matches
/// выше cutoff (UI пагинирует по 20).
nonisolated struct SearchResults: Sendable, Equatable {
    let authors: [AuthorMatch]
    let series:  [SeriesMatch]
    let books:   [BookMatch]
}
