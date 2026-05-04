import Foundation

/// Параллельный fuzzy-скан по `Library`. `nonisolated` чтобы можно было
/// вызывать с любого actor'а (в т.ч. из `Task.detached` фоновой задачи).
///
/// Engine не вводит каких-либо собственных лимитов на количество matches —
/// возвращает всё, что прошло `FuzzyScorer.SCORE_CUTOFF`. Пагинация и
/// cap-логика — чисто UI-уровня (см. `SearchCoordinator` /
/// `SearchResultListView`). Это прямо соответствует спеке (§ Группы —
/// «по умолчанию топ-10 + Показать всех»; cap живёт в UI, не в engine).
nonisolated enum SearchEngine {
    static func run(query: String, language: String, in lib: Library) -> SearchResults {
        let qToks = SearchPreprocess.tokens(query)
        guard !qToks.isEmpty else {
            return SearchResults(authors: [], series: [], books: [])
        }
        let qPatterns = qToks.map(FuzzyScorer.LcsPattern.init)

        // 1. Authors — все matches выше cutoff, отсортированные по убыванию.
        let authorHits = parallelScan(
            qPatterns: qPatterns,
            count: lib.authors.count,
            cutoff: FuzzyScorer.SCORE_CUTOFF
        ) { i in
            lib.searchKeyAuthors[i]
        }
        let authors = authorHits.map { AuthorMatch(authorIndex: $0.index, score: $0.score) }

        // 2. Series
        let seriesHits = parallelScan(
            qPatterns: qPatterns,
            count: lib.series.count,
            cutoff: FuzzyScorer.SCORE_CUTOFF
        ) { i in
            lib.searchKeySeries[i]
        }
        let series = seriesHits.map { SeriesMatch(seriesIndex: $0.index, score: $0.score) }

        // 3. Books — language-filtered, combined key (title + author tokens + series tokens).
        let bookHits = parallelScanBooks(
            qPatterns: qPatterns,
            language: language,
            in: lib,
            cutoff: FuzzyScorer.SCORE_CUTOFF
        )
        let books = bookHits.map { BookMatch(bookIndex: $0.index, score: $0.score) }

        return SearchResults(authors: authors, series: series, books: books)
    }

    // MARK: - Internal helpers

    /// Internal scoring hit — индекс в исходном массиве + скор.
    /// `Sendable`: пересекает actor boundary внутри `concurrentPerform`.
    private struct Hit: Sendable {
        let index: Int
        let score: Double
    }

    /// Generic параллельный скан: choice — единый массив токенов на индекс
    /// (авторы и серии). Книги используют отдельный путь
    /// `parallelScanBooks` с объединением title+author+series tokens.
    private static func parallelScan(
        qPatterns: [FuzzyScorer.LcsPattern],
        count: Int,
        cutoff: Double,
        keyAt: (Int) -> [[UInt32]]
    ) -> [Hit] {
        if count == 0 { return [] }
        let cores = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let chunkSize = (count + cores - 1) / cores
        var perChunk: [[Hit]] = Array(repeating: [], count: cores)
        perChunk.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: cores) { c in
                let lo = c * chunkSize
                let hi = min(lo + chunkSize, count)
                if lo >= hi { return }
                var local: [Hit] = []
                local.reserveCapacity(64)
                for i in lo..<hi {
                    let key = keyAt(i)
                    let s = FuzzyScorer.tokenMinRatioPre(
                        qPatterns: qPatterns, cTokens: key, cutoff: cutoff)
                    if s >= cutoff { local.append(Hit(index: i, score: s)) }
                }
                buf[c] = local
            }
        }
        var hits = perChunk.flatMap { $0 }
        hits.sort { $0.score > $1.score }
        return hits
    }

    /// Книжный скан с объединением title + author tokens + series tokens
    /// на каждой итерации. Дополнительно фильтрует по языку.
    private static func parallelScanBooks(
        qPatterns: [FuzzyScorer.LcsPattern],
        language: String,
        in lib: Library,
        cutoff: Double
    ) -> [Hit] {
        let n = lib.books.count
        if n == 0 { return [] }
        // Sentinel for "language not specified" matches main-window convention.
        let langKey = language == BooksByContext.unspecifiedLanguageToken ? "" : language
        let cores = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let chunkSize = (n + cores - 1) / cores
        var perChunk: [[Hit]] = Array(repeating: [], count: cores)
        perChunk.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: cores) { c in
                let lo = c * chunkSize
                let hi = min(lo + chunkSize, n)
                if lo >= hi { return }
                var local: [Hit] = []
                local.reserveCapacity(128)
                var combined: [[UInt32]] = []
                combined.reserveCapacity(16)
                for i in lo..<hi {
                    if lib.books[i].language != langKey { continue }
                    combined.removeAll(keepingCapacity: true)
                    combined.append(contentsOf: lib.searchKeyTitle[i])
                    let aIdx = Int(lib.searchAuthorIdx[i])
                    if aIdx >= 0 {
                        combined.append(contentsOf: lib.searchKeyAuthors[aIdx])
                    }
                    let sIdx = Int(lib.searchSeriesIdx[i])
                    if sIdx >= 0 {
                        combined.append(contentsOf: lib.searchKeySeries[sIdx])
                    }
                    let s = FuzzyScorer.tokenMinRatioPre(
                        qPatterns: qPatterns, cTokens: combined, cutoff: cutoff)
                    if s >= cutoff { local.append(Hit(index: i, score: s)) }
                }
                buf[c] = local
            }
        }
        var hits = perChunk.flatMap { $0 }
        hits.sort { $0.score > $1.score }
        return hits
    }
}
