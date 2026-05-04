import Foundation

/// Параллельный fuzzy-скан по `Library`. `nonisolated` чтобы можно было
/// вызывать с любого actor'а (в т.ч. из `Task.detached` фоновой задачи).
///
/// Engine не вводит каких-либо собственных лимитов на количество matches —
/// возвращает всё, что прошло `FuzzyScorer.scoreCutoff`. Пагинация и
/// cap-логика — чисто UI-уровня (см. `SearchCoordinator` /
/// `SearchResultListView`). Это прямо соответствует спеке (§ Группы —
/// «по умолчанию топ-10 + Показать всех»; cap живёт в UI, не в engine).
nonisolated enum SearchEngine {
    nonisolated static func run(query: String, language: String, in lib: Library) -> SearchResults {
        let qToks = SearchPreprocess.tokens(query)
        guard !qToks.isEmpty else {
            return SearchResults(authors: [], series: [], books: [])
        }

        // 1. Authors — все matches выше cutoff, отсортированные по убыванию.
        let authorHits = parallelScan(
            qTokens: qToks,
            count: lib.authors.count,
            cutoff: FuzzyScorer.scoreCutoff
        ) { i in
            lib.searchKeyAuthors[i]
        }
        let authors = authorHits.map { AuthorMatch(authorIndex: $0.index, score: $0.score) }

        // 2. Series — uses extended key (series name + author tokens) so
        // cross-token queries like «сандерсон мстители» match series whose
        // author is Сандерсон.
        let seriesHits = parallelScan(
            qTokens: qToks,
            count: lib.series.count,
            cutoff: FuzzyScorer.scoreCutoff
        ) { i in
            lib.searchKeySeriesExt[i]
        }
        let series = seriesHits.map { SeriesMatch(seriesIndex: $0.index, score: $0.score) }

        // 3. Books — language-filtered, combined key (title + author tokens + series tokens).
        let bookHitsAll = parallelScanBooks(
            qTokens: qToks,
            language: language,
            in: lib,
            cutoff: FuzzyScorer.scoreCutoff
        )
        // Дедуп с авторами/сериями: книги, чей автор/серия уже сматчились
        // отдельно, видны в их блоках — в bucket не дублируем.
        let matchedAuthorIDs = Set(authorHits.map { lib.authors[$0.index].id })
        let matchedSeriesIDs = Set(seriesHits.map { lib.series[$0.index].id })
        let bookHits = filterBookHitsAgainstMatched(
            bookHitsAll,
            in: lib,
            matchedAuthorIDs: matchedAuthorIDs,
            matchedSeriesIDs: matchedSeriesIDs
        )
        let books = bookHits.map { BookMatch(bookIndex: $0.index, score: $0.score) }

        return SearchResults(authors: authors, series: series, books: books)
    }

    // MARK: - Internal helpers

    /// Internal scoring hit — индекс в исходном массиве + скор.
    /// `Sendable`: пересекает actor boundary внутри `concurrentPerform`.
    nonisolated private struct Hit: Sendable {
        let index: Int
        let score: Double
    }

    /// `@unchecked Sendable` обёртка над `UnsafeMutableBufferPointer`. Каждый
    /// поток `concurrentPerform` пишет в свой непересекающийся слот `buf[c]`
    /// — алгоритм безопасен, но компилятор не может это доказать (структура
    /// `UnsafeMutableBufferPointer` не Sendable). Эта обёртка явно говорит
    /// «trust me, я знаю, что делаю» — стандартный idiom при использовании
    /// сырых указателей внутри @Sendable-замыканий.
    nonisolated private struct SendableBuf<T>: @unchecked Sendable {
        let buf: UnsafeMutableBufferPointer<T>
    }

    /// Generic параллельный скан: choice — единый массив токенов на индекс
    /// (авторы и серии). Книги используют отдельный путь
    /// `parallelScanBooks` с объединением title+author+series tokens.
    nonisolated private static func parallelScan(
        qTokens: [[UInt32]],
        count: Int,
        cutoff: Double,
        keyAt: (Int) -> [[UInt32]]
    ) -> [Hit] {
        if count == 0 { return [] }
        let cores = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let chunkSize = (count + cores - 1) / cores
        var perChunk: [[Hit]] = Array(repeating: [], count: cores)
        perChunk.withUnsafeMutableBufferPointer { rawBuf in
            let wrapped = SendableBuf(buf: rawBuf)
            DispatchQueue.concurrentPerform(iterations: cores) { c in
                let lo = c * chunkSize
                let hi = min(lo + chunkSize, count)
                if lo >= hi { return }
                var local: [Hit] = []
                local.reserveCapacity(64)
                for i in lo..<hi {
                    let key = keyAt(i)
                    let s = FuzzyScorer.tokenMinRatioCut(
                        qTokens: qTokens, cTokens: key, cutoff: cutoff)
                    if s >= cutoff { local.append(Hit(index: i, score: s)) }
                }
                wrapped.buf[c] = local
            }
        }
        var hits = perChunk.flatMap { $0 }
        hits.sort { $0.score > $1.score }
        return hits
    }

    /// Книжный скан с объединением title + author tokens + series tokens.
    /// Combined key нужен, чтобы запросы вроде «Толстой Война» находили
    /// «Войну и мир»: ни автор «Толстой Лев Николаевич» (нет токена «война»),
    /// ни заголовок «Война и мир» (нет токена «толстой») не пройдут по
    /// отдельности — а combined ключ книги [война, и, мир, толстой, лев,
    /// николаевич] матчит оба query-токена идеально. Дополнительно
    /// фильтрует по языку. Дедуп с авторско-серийными бакетами делается
    /// постфактум в `run` через `filterBookHitsAgainstMatched`.
    nonisolated private static func parallelScanBooks(
        qTokens: [[UInt32]],
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
        perChunk.withUnsafeMutableBufferPointer { rawBuf in
            let wrapped = SendableBuf(buf: rawBuf)
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
                    let s = FuzzyScorer.tokenMinRatioCut(
                        qTokens: qTokens, cTokens: combined, cutoff: cutoff)
                    if s >= cutoff { local.append(Hit(index: i, score: s)) }
                }
                wrapped.buf[c] = local
            }
        }
        var hits = perChunk.flatMap { $0 }
        hits.sort { $0.score > $1.score }
        return hits
    }

    /// Убирает из book-bucket'а книги, чей автор уже сматчился отдельно в
    /// authors-bucket или серия — в series-bucket. Такие книги остаются
    /// видимыми внутри блока соответствующего автора/серии — нет смысла
    /// дублировать их в bucket'е книг. Стоимость: O(books) с O(1)
    /// hash-lookup на каждую (Set<Int32>.contains), вне зависимости от
    /// размера matched-сетов.
    nonisolated private static func filterBookHitsAgainstMatched(
        _ hits: [Hit],
        in lib: Library,
        matchedAuthorIDs: Set<Int32>,
        matchedSeriesIDs: Set<Int32>
    ) -> [Hit] {
        if matchedAuthorIDs.isEmpty && matchedSeriesIDs.isEmpty { return hits }
        return hits.filter { hit in
            let b = lib.books[hit.index]
            if !matchedAuthorIDs.isEmpty {
                for aid in b.authorIDs where matchedAuthorIDs.contains(aid) {
                    return false
                }
            }
            if let sid = b.seriesID, matchedSeriesIDs.contains(sid) {
                return false
            }
            return true
        }
    }
}
