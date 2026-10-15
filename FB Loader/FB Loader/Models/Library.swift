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
    let authorByID: [Int32: Author]     // O(1) lookup, used by BookDetail and table rows
    let seriesByID: [Int32: Series]     // O(1) lookup
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

    /// Per-language book counts. `bookCountByAuthorByLang[authorID]?[lang]`
    /// gives N books that author has in that language. Used by the sidebar
    /// to hide authors whose entire output is in some other language than
    /// the current filter, and to render language-aware "(N)" counters.
    let bookCountByAuthorByLang: [Int32: [String: Int]]
    let bookCountBySeriesByLang: [Int32: [String: Int]]

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
    // `searchAuthorIdx` / `searchSeriesIdx` lookups.
    let searchKeyAuthors: TokenStore  // parallel to authors
    let searchKeySeries:  TokenStore  // parallel to series — base key, used by parallelScanBooks combined key
    /// Extended series key: base series tokens + tokens of all distinct
    /// authors with at least one book in the series. Used only by
    /// `SearchEngine.parallelScan` for the Series bucket so cross-token
    /// queries like «сандерсон мстители» match series «Мстители» whose
    /// author is Сандерсон.
    let searchKeySeriesExt: TokenStore
    let searchKeyTitle:   TokenStore  // parallel to books
    let searchAuthorIdx:  [Int32]       // per book: index into searchKeyAuthors, -1 if missing
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
        self.authorByID = Dictionary(uniqueKeysWithValues: authors.map { ($0.id, $0) })
        self.seriesByID = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        self.genreByID = Dictionary(uniqueKeysWithValues: genres.map { ($0.id, $0) })
        // `Dictionary(uniqueKeysWithValues:)` would crash on duplicate libids;
        // freeLib emits unique LIBIDs but we tolerate dup-keep-first defensively.
        var bookIndex: [Int32: Int32] = [:]
        bookIndex.reserveCapacity(books.count)
        for (i, b) in books.enumerated() where bookIndex[b.libid] == nil { bookIndex[b.libid] = Int32(i) }
        self.bookIndexByLibid = bookIndex
        print("[Library.init] *ByID dicts built")
        onStatus?("[Library.init] *ByID dicts built")

        var byAuthor: [Int32: [Int]] = [:]
        var bySeries: [Int32: [Int]] = [:]
        var byGenre: [Int16: [Int]] = [:]
        var langSet = Set<String>()
        var byAuthorLang: [Int32: [String: Int]] = [:]
        var bySeriesLang: [Int32: [String: Int]] = [:]
        var byGenreLang: [Int16: [String: Int]] = [:]
        for (i, b) in books.enumerated() {
            for aid in b.authorIDs {
                byAuthor[aid, default: []].append(i)
                byAuthorLang[aid, default: [:]][b.language, default: 0] += 1
            }
            if let sid = b.seriesID {
                bySeries[sid, default: []].append(i)
                bySeriesLang[sid, default: [:]][b.language, default: 0] += 1
            }
            for gid in b.genreIDs {
                byGenre[gid, default: []].append(i)
                byGenreLang[gid, default: [:]][b.language, default: 0] += 1
            }
            langSet.insert(b.language)
        }
        self.booksByAuthor = byAuthor
        self.booksBySeries = bySeries
        self.booksByGenre = byGenre
        self.bookCountByAuthorByLang = byAuthorLang
        self.bookCountBySeriesByLang = bySeriesLang
        self.bookCountByGenreByLang = byGenreLang
        self.languages = Array(langSet).sorted()
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
        print("[Library.init] secondary indices built; \(langSet.count) distinct languages")
        onStatus?("[Library.init] secondary indices built; \(langSet.count) distinct languages")

        // Search-ключи строятся синхронно — пользователь видит «Считаем
        // индексы поиска…» как часть нормальной загрузки каталога. Стоимость
        // ~2 с на полном каталоге.
        let searchStatus = "Считаем индексы поиска…"
        print("[Library.init] \(searchStatus)")
        onStatus?(searchStatus)

        var sAuthors = TokenStore()
        for a in authors {
            sAuthors.appendTokenized(a.displayName)
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
        var aIdx: [Int32] = []
        aIdx.reserveCapacity(books.count)
        var sIdx: [Int32] = []
        sIdx.reserveCapacity(books.count)
        // Lookup tables: id → index (мы уже строили *byID Dictionary, но
        // нам нужен индекс в массивах authors/series, не сам объект).
        var authorIndexByID: [Int32: Int] = [:]
        authorIndexByID.reserveCapacity(authors.count)
        for (i, a) in authors.enumerated() { authorIndexByID[a.id] = i }
        var seriesIndexByID: [Int32: Int] = [:]
        seriesIndexByID.reserveCapacity(series.count)
        for (i, s) in series.enumerated() { seriesIndexByID[s.id] = i }
        for b in books {
            sTitles.appendTokenized(b.title)
            // Primary author: first authorID; -1 if missing.
            if let firstAID = b.authorIDs.first,
               let idx = authorIndexByID[firstAID] {
                aIdx.append(Int32(idx))
            } else {
                aIdx.append(-1)
            }
            if let sid = b.seriesID, let idx = seriesIndexByID[sid] {
                sIdx.append(Int32(idx))
            } else {
                sIdx.append(-1)
            }
        }
        sTitles.shrink()
        self.searchKeyTitle = sTitles
        self.searchAuthorIdx = aIdx
        self.searchSeriesIdx = sIdx

        // Series-bucket extended key: for each series, append the tokens of
        // every distinct author with at least one book in that series. Cost
        // ~10 МБ on the full catalog. Lets cross-token queries («сандерсон
        // мстители») match a series by combining its name with its authors.
        var authorIdxBySeriesIdx: [Set<Int32>] = Array(repeating: [], count: series.count)
        for k in 0..<books.count {
            let sIdxK = sIdx[k]
            if sIdxK < 0 { continue }
            let aIdxK = aIdx[k]
            if aIdxK < 0 { continue }
            authorIdxBySeriesIdx[Int(sIdxK)].insert(aIdxK)
        }
        var sSeriesExt = TokenStore()
        sSeries.withView { seriesView in
            sAuthors.withView { authorsView in
                var ext: [UnsafeBufferPointer<UInt32>] = []
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
}
