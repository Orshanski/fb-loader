import Foundation

/// Один матч-автор: индекс в `Library.authors` + скор 0..100 (уже не ниже `FuzzyScorer.scoreCutoff`).
nonisolated struct AuthorMatch: Sendable, Equatable {
    let authorIndex: Int
    let score: Double
}

nonisolated struct SeriesMatch: Sendable, Equatable {
    let seriesIndex: Int
    let score: Double
}

nonisolated struct BookMatch: Sendable, Equatable {
    let bookIndex: Int
    let score: Double
}

/// Бакеты отсортированы по убыванию скора и содержат все matches выше cutoff; ограничение показа — в UI.
nonisolated struct SearchResults: Sendable, Equatable {
    let authors: [AuthorMatch]
    let series:  [SeriesMatch]
    let books:   [BookMatch]
}
