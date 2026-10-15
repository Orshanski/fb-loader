import Foundation

/// In-memory snapshot of the entire catalog. Built by `INPXImporter`,
/// persisted as a binary cache, queried by the UI.
/// All stored properties are `let`s of Sendable value types, so the
/// instance is safely shareable across actors after `init`.
nonisolated final class Library: Sendable {
    let inpxHash: Data           // SHA-256 of INPX content
    let inpxVersion: String      // contents of version.info ("20260301" etc.)
    let archives: [String]       // .zip filenames (without extension), indexed by archiveIndex
    let authors: [Author]        // sorted by lastName, then firstName
    let series: [Series]         // sorted by name
    let genres: [Genre]
    let books: [Book]

    // Secondary indices (built once, after load):
    // Номера в `authors`/`series`, а не копии: копия 171k `Author` стоила ~24 МБ.
    private let authorIndexByID: [Int32: Int32]
    private let seriesIndexByID: [Int32: Int32]
    let genreByID: [Int16: Genre]       // O(1) lookup
    /// Номер в `books`, а не копия книги: вторая копия 594k `Book` стоила десятки МБ.
    private let bookIndexByLibid: [Int32: Int32]
    let booksByAuthor: [Int32: [Int]]   // authorID → indices into `books`
    let booksBySeries: [Int32: [Int]]
    let booksByGenre: [Int16: [Int]]
    let bookCountByGenreByLang: [Int16: [String: Int]]
    let rootGenres: [Genre]
    let childGenresByParent: [Int16: [Genre]]
    let orphanGenres: [Genre]
    let sidebarGenres: [Genre]
    let languages: [String]             // distinct languages found, sorted

    private let languageIndex: [String: UInt16]
    private let authorLanguageCounts: LanguageCounts
    private let seriesLanguageCounts: LanguageCounts

    // Lowercased names parallel to `authors` / `series`, computed once at
    // `init` time. Used by sidebar filter (AuthorsListView / SeriesListView)
    // to avoid `displayName.lowercased()` allocation on every keystroke
    // across 100k+ authors. Transient: NOT persisted in LibraryBinaryCodec.
    let lowercasedAuthorNames: [String]
    let lowercasedSeriesNames: [String]
    let lowercasedGenreNames: [Int16: String]
    let lowercasedSidebarGenreNames: [String]

    // MARK: - Search index (transient, built in init, NOT persisted)
    //
    // Token-level fuzzy-search keys, parallel to authors / series / books,
    // tokens from `SearchPreprocess.tokens` packed into `TokenStore`, built once at init.
    // Light variant: per-book keeps only title tokens; for
    // book scoring the engine dispatches author/series tokens via
    // `bookAuthorStarts`/`bookAuthorIndices` / `searchSeriesIdx` lookups.
    // Псевдо-автор «(Без автора)» в поиске не участвует: пустой ключ, в ключи книг и серий не входит.
    let searchKeyAuthors: TokenStore  // parallel to authors
    let searchKeySeries:  TokenStore  // parallel to series — base key, used by parallelScanBooks combined key
    /// Extended series key: base series tokens + tokens of all distinct
    /// authors with at least one book in the series. Used only by
    /// `SearchEngine.parallelScan` for the Series bucket so cross-token
    /// queries like «сандерсон мстители» match series «Мстители» whose
    /// author is Сандерсон.
    let searchKeySeriesExt: TokenStore
    let searchKeyTitle:   TokenStore  // parallel to books
    /// Авторы книги `i` — `bookAuthorIndices[bookAuthorStarts[i]..<bookAuthorStarts[i+1]]`,
    /// номера в `authors`; плоско, а не массив на книгу — 594k мелких массивов дороже.
    let bookAuthorStarts: [UInt32]
    let bookAuthorIndices: [Int32]
    let searchSeriesIdx:  [Int32]       // per book: index into searchKeySeries, -1 if no series

    init(
        inpxHash: Data,
        inpxVersion: String,
        archives: [String],
        authors: [Author],
        series: [Series],
        genres: [Genre],
        books: [Book],
        onStatus: (@Sendable (String) -> Void)? = nil
    ) {
        self.inpxHash = inpxHash
        self.inpxVersion = inpxVersion
        self.archives = archives
        self.authors = authors
        self.series = series
        self.genres = genres
        self.books = books

        // Build secondary indices.
        // INPXImporter (Phase 3) is responsible for ID uniqueness in `authors`,
        // `series` and `genres`. Duplicates here would crash via Dictionary's
        // uniqueness precondition — that crash is the contract violation signal.
        let startStatus = "[Library.init] start: \(books.count) books, \(authors.count) authors, \(series.count) series, \(genres.count) genres"
        print(startStatus)
        onStatus?(startStatus)
        var authorIndexByID: [Int32: Int32] = [:]
        authorIndexByID.reserveCapacity(authors.count)
        for (i, a) in authors.enumerated() { authorIndexByID[a.id] = Int32(i) }
        self.authorIndexByID = authorIndexByID
        var seriesIndexByID: [Int32: Int32] = [:]
        seriesIndexByID.reserveCapacity(series.count)
        for (i, s) in series.enumerated() { seriesIndexByID[s.id] = Int32(i) }
        self.seriesIndexByID = seriesIndexByID
        self.genreByID = Dictionary(uniqueKeysWithValues: genres.map { ($0.id, $0) })
        // `Dictionary(uniqueKeysWithValues:)` would crash on duplicate libids;
        // freeLib emits unique LIBIDs but we tolerate dup-keep-first defensively.
        var bookIndex: [Int32: Int32] = [:]
        bookIndex.reserveCapacity(books.count)
        for (i, b) in books.enumerated() where bookIndex[b.libid] == nil { bookIndex[b.libid] = Int32(i) }
        self.bookIndexByLibid = bookIndex
        print("[Library.init] *ByID dicts built")
        onStatus?("[Library.init] *ByID dicts built")

        let languages = Array(Set(books.map(\.language))).sorted()
        // Сверх 65 535 языков (мусор в INPX) делят последний номер — счётчики, но не падение.
        let languageIndex = Dictionary(uniqueKeysWithValues: languages.enumerated().map { ($1, UInt16(clamping: $0)) })
        var byAuthor: [Int32: [Int]] = [:]
        var bySeries: [Int32: [Int]] = [:]
        var byGenre: [Int16: [Int]] = [:]
        var authorLangKeys: [UInt64] = [], seriesLangKeys: [UInt64] = []
        var byGenreLang: [Int16: [String: Int]] = [:]
        for (i, b) in books.enumerated() {
            let lang = UInt64(languageIndex[b.language]!)
            for aid in b.authorIDs {
                byAuthor[aid, default: []].append(i)
                if let a = authorIndexByID[aid] { authorLangKeys.append(UInt64(a) << 16 | lang) }
            }
            if let sid = b.seriesID {
                bySeries[sid, default: []].append(i)
                if let s = seriesIndexByID[sid] { seriesLangKeys.append(UInt64(s) << 16 | lang) }
            }
            for gid in b.genreIDs {
                byGenre[gid, default: []].append(i)
                byGenreLang[gid, default: [:]][b.language, default: 0] += 1
            }
        }
        self.booksByAuthor = byAuthor
        self.booksBySeries = bySeries
        self.booksByGenre = byGenre
        self.authorLanguageCounts = LanguageCounts(entityCount: authors.count, keys: authorLangKeys)
        self.seriesLanguageCounts = LanguageCounts(entityCount: series.count, keys: seriesLangKeys)
        self.bookCountByGenreByLang = byGenreLang
        self.languages = languages
        self.languageIndex = languageIndex
        self.lowercasedAuthorNames = authors.map { $0.displayName.lowercased() }
        self.lowercasedSeriesNames = series.map { $0.name.lowercased() }
        self.lowercasedGenreNames = Dictionary(uniqueKeysWithValues: genres.map { ($0.id, $0.name.lowercased()) })

        let rootGenres = genres.filter { $0.parentID == nil }
        let rootIDs = Set(rootGenres.map(\.id))
        let parentByID = Dictionary(uniqueKeysWithValues: genres.map { ($0.id, $0.parentID) })

        func nearestRootID(for genre: Genre) -> Int16? {
            var seen = Set<Int16>()
            var current = genre.parentID
            while let id = current {
                if rootIDs.contains(id) { return id }
                if seen.contains(id) { return nil }
                seen.insert(id)
                current = parentByID[id] ?? nil
            }
            return nil
        }

        self.rootGenres = rootGenres
        var childrenByRoot: [Int16: [Genre]] = [:]
        var orphans: [Genre] = []
        for genre in genres where genre.parentID != nil {
            if let rootID = nearestRootID(for: genre) {
                childrenByRoot[rootID, default: []].append(genre)
            } else {
                orphans.append(genre)
            }
        }
        self.childGenresByParent = childrenByRoot
        self.orphanGenres = orphans
        let sidebarGenres = rootGenres.flatMap { root in
            [root] + (childrenByRoot[root.id] ?? [])
        } + orphans
        self.sidebarGenres = sidebarGenres
        self.lowercasedSidebarGenreNames = sidebarGenres.map { $0.name.lowercased() }
        print("[Library.init] secondary indices built; \(languages.count) distinct languages")
        onStatus?("[Library.init] secondary indices built; \(languages.count) distinct languages")

        // Search-ключи строятся синхронно — пользователь видит «Считаем
        // индексы поиска…» как часть нормальной загрузки каталога. Стоимость
        // ~2 с на полном каталоге.
        let searchStatus = "Считаем индексы поиска…"
        print("[Library.init] \(searchStatus)")
        onStatus?(searchStatus)

        var sAuthors = TokenStore()
        for a in authors {
            sAuthors.appendTokenized(a.id == Author.unknownID ? "" : a.displayName)
        }
        sAuthors.shrink()
        self.searchKeyAuthors = sAuthors

        var sSeries = TokenStore()
        for s in series {
            sSeries.appendTokenized(s.name)
        }
        sSeries.shrink()
        self.searchKeySeries = sSeries

        var sTitles = TokenStore()
        var aStarts: [UInt32] = [0]
        aStarts.reserveCapacity(books.count + 1)
        var aIndices: [Int32] = []
        aIndices.reserveCapacity(books.count)
        var sIdx: [Int32] = []
        sIdx.reserveCapacity(books.count)
        var authorIdxBySeriesIdx: [Set<Int32>] = Array(repeating: [], count: series.count)
        for b in books {
            sTitles.appendTokenized(b.title)
            let first = aIndices.count
            for aid in b.authorIDs where aid != Author.unknownID {
                guard let idx = authorIndexByID[aid], !aIndices[first...].contains(idx) else { continue }
                aIndices.append(idx)
            }
            aStarts.append(UInt32(aIndices.count))
            if let sid = b.seriesID, let idx = seriesIndexByID[sid] {
                sIdx.append(idx)
                // Ext-ключ серии: имя + токены всех различных авторов её книг — для запросов
                // «автор + серия» вроде «сандерсон мстители».
                authorIdxBySeriesIdx[Int(idx)].formUnion(aIndices[first...])
            } else {
                sIdx.append(-1)
            }
        }
        sTitles.shrink()
        self.searchKeyTitle = sTitles
        self.bookAuthorStarts = aStarts
        self.bookAuthorIndices = aIndices.withUnsafeBufferPointer(Array.init)
        self.searchSeriesIdx = sIdx

        var sSeriesExt = TokenStore()
        sSeries.withView { seriesView in
            sAuthors.withView { authorsView in
                var ext: [SearchToken] = []
                for i in 0..<series.count {
                    ext.removeAll(keepingCapacity: true)
                    seriesView.appendTokens(of: i, to: &ext)
                    for aIdxOfSeries in authorIdxBySeriesIdx[i] {
                        authorsView.appendTokens(of: Int(aIdxOfSeries), to: &ext)
                    }
                    sSeriesExt.append(ext)
                }
            }
        }
        sSeriesExt.shrink()
        self.searchKeySeriesExt = sSeriesExt

        print("[Library.init] search indices built")
        onStatus?("[Library.init] search indices built")
    }

    func book(libid: Int32) -> Book? {
        bookIndexByLibid[libid].map { books[Int($0)] }
    }

    func author(id: Int32) -> Author? {
        authorIndexByID[id].map { authors[Int($0)] }
    }

    func series(id: Int32) -> Series? {
        seriesIndexByID[id].map { series[Int($0)] }
    }

    func bookCount(authorID: Int32, language: String) -> Int {
        guard let a = authorIndexByID[authorID], let l = languageIndex[language] else { return 0 }
        return authorLanguageCounts.count(entity: Int(a), language: l)
    }

    func bookCount(seriesID: Int32, language: String) -> Int {
        guard let s = seriesIndexByID[seriesID], let l = languageIndex[language] else { return 0 }
        return seriesLanguageCounts.count(entity: Int(s), language: l)
    }
}
