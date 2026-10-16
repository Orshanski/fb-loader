import Foundation

/// Параллельный fuzzy-скан по `Library`. Возвращает все matches выше `FuzzyScorer.scoreCutoff`:
/// ограничение показа и пагинация — только в UI (`SearchCoordinator`, `SearchResultListView`).
nonisolated enum SearchEngine {
    nonisolated static func run(query: String, language: String, in lib: Library) -> SearchResults {
        var qStore = TokenStore()
        qStore.appendTokenized(query)
        return qStore.withView { qView in
            var q: [SearchToken] = []
            qView.appendTokens(of: 0, to: &q)
            if q.isEmpty { return SearchResults(authors: [], series: [], books: []) }
            return run(qTokens: q, language: language, in: lib)
        }
    }

    nonisolated private static func run(qTokens qToks: [SearchToken],
                                        language: String, in lib: Library) -> SearchResults {

        let langKey = BooksByContext.languageKey(language)

        // 1. Authors — все matches выше cutoff, отсортированные по убыванию;
        // без книг на выбранном языке блок автора был бы пустым.
        let authorHits = parallelScan(qTokens: qToks, keys: lib.searchKeyAuthors,
                                      cutoff: FuzzyScorer.scoreCutoff)
            .filter { lib.bookCount(authorID: lib.authors[$0.index].id, language: langKey) > 0 }
        let authors = authorHits.map { AuthorMatch(authorIndex: $0.index, score: $0.score) }

        // 2. Series use the extended key (name + author tokens) so «сандерсон мстители» matches.
        let seriesHits = parallelScan(qTokens: qToks, keys: lib.searchKeySeriesExt,
                                      cutoff: FuzzyScorer.scoreCutoff)
            .filter { lib.bookCount(seriesID: lib.series[$0.index].id, language: langKey) > 0 }
        let series = seriesHits.map { SeriesMatch(seriesIndex: $0.index, score: $0.score) }

        let bookHitsAll = parallelScanBooks(
            qTokens: qToks,
            language: langKey,
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

    /// Кусков вчетверо больше ядер: один медленный кусок (длинные ключи) не держит остальные ядра.
    nonisolated private static var chunkCount: Int {
        4 * max(2, ProcessInfo.processInfo.activeProcessorCount)
    }

    nonisolated private struct Hit: Sendable {
        let index: Int
        let score: Double
    }

    /// Каждый воркер `concurrentPerform` пишет в свой слот `buf[c]`; компилятор этого доказать не может.
    nonisolated private struct SendableBuf<T>: @unchecked Sendable {
        let buf: UnsafeMutableBufferPointer<T>
    }

    /// Указатели на неизменяемые массивы `Library` — во время скана только читаются.
    nonisolated private struct SendablePtr<T>: @unchecked Sendable {
        let buf: UnsafeBufferPointer<T>
    }

    /// Слова запроса — только чтение во время скана.
    nonisolated private struct SendableTokens: @unchecked Sendable {
        let tokens: [SearchToken]
    }

    /// Авторы и серии; книги идут через `parallelScanBooks`.
    nonisolated private static func parallelScan(
        qTokens: [SearchToken],
        keys: TokenStore,
        cutoff: Double
    ) -> [Hit] {
        let count = keys.count
        if count == 0 { return [] }
        let qTokens = SendableTokens(tokens: qTokens)
        let chunks = chunkCount
        let chunkSize = (count + chunks - 1) / chunks
        var perChunk: [[Hit]] = Array(repeating: [], count: chunks)
        keys.withView { view in
            perChunk.withUnsafeMutableBufferPointer { rawBuf in
                let wrapped = SendableBuf(buf: rawBuf)
                DispatchQueue.concurrentPerform(iterations: chunks) { c in
                    let lo = c * chunkSize
                    let hi = min(lo + chunkSize, count)
                    if lo >= hi { return }
                    var local: [Hit] = []
                    local.reserveCapacity(64)
                    var key: [SearchToken] = []
                    for i in lo..<hi {
                        key.removeAll(keepingCapacity: true)
                        view.appendTokens(of: i, to: &key)
                        let s = FuzzyScorer.tokenMinRatioCut(
                            qTokens: qTokens.tokens, cTokens: key, cutoff: cutoff)
                        if s >= cutoff { local.append(Hit(index: i, score: s)) }
                    }
                    wrapped.buf[c] = local
                }
            }
        }
        var hits = perChunk.flatMap { $0 }
        hits.sort { $0.score > $1.score }
        return hits
    }

    /// Ключ книги — токены title + author + series: «Толстой Война» находит «Войну и мир», хотя ни автор,
    /// ни заголовок по отдельности не содержат оба токена. Фильтрует по языку; дедуп с блоками авторов/серий —
    /// в `run` через `filterBookHitsAgainstMatched`.
    nonisolated private static func parallelScanBooks(
        qTokens: [SearchToken],
        language: String,
        in lib: Library,
        cutoff: Double
    ) -> [Hit] {
        let n = lib.books.count
        if n == 0 { return [] }
        let qTokens = SendableTokens(tokens: qTokens)
        let chunks = chunkCount
        let chunkSize = (n + chunks - 1) / chunks
        var perChunk: [[Hit]] = Array(repeating: [], count: chunks)
        lib.bookAuthorStarts.withUnsafeBufferPointer { startsBuf in
            lib.bookAuthorIndices.withUnsafeBufferPointer { indicesBuf in
                let aStarts = SendablePtr(buf: startsBuf), aIndices = SendablePtr(buf: indicesBuf)
                lib.searchKeyTitle.withView { titles in
                    lib.searchKeyAuthors.withView { authors in
                        lib.searchKeySeries.withView { series in
                            perChunk.withUnsafeMutableBufferPointer { rawBuf in
                                let wrapped = SendableBuf(buf: rawBuf)
                                DispatchQueue.concurrentPerform(iterations: chunks) { c in
                                    let lo = c * chunkSize
                                    let hi = min(lo + chunkSize, n)
                                    if lo >= hi { return }
                                    var local: [Hit] = []
                                    local.reserveCapacity(128)
                                    var combined: [SearchToken] = []
                                    combined.reserveCapacity(16)
                                    for i in lo..<hi {
                                        if lib.books[i].language != language { continue }
                                        combined.removeAll(keepingCapacity: true)
                                        titles.appendTokens(of: i, to: &combined)
                                        for a in Int(aStarts.buf[i])..<Int(aStarts.buf[i + 1]) {
                                            authors.appendTokens(of: Int(aIndices.buf[a]), to: &combined)
                                        }
                                        let sIdx = Int(lib.searchSeriesIdx[i])
                                        if sIdx >= 0 { series.appendTokens(of: sIdx, to: &combined) }
                                        let s = FuzzyScorer.tokenMinRatioCut(
                                            qTokens: qTokens.tokens, cTokens: combined, cutoff: cutoff)
                                        if s >= cutoff { local.append(Hit(index: i, score: s)) }
                                    }
                                    wrapped.buf[c] = local
                                }
                            }
                        }
                    }
                }
            }
        }
        var hits = perChunk.flatMap { $0 }
        hits.sort { $0.score > $1.score }
        return hits
    }

    /// Убирает из бакета книг те, чей автор или серия уже сматчились: они видны в своих блоках.
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
