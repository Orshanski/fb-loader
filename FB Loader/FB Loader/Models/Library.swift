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
    let bookByLibid: [Int32: Book]      // O(1) book lookup — was a hot 700k-scan
    let booksByAuthor: [Int32: [Int]]   // authorID → indices into `books`
    let booksBySeries: [Int32: [Int]]
    let bookCountByAuthor: [Int32: Int] // for the "(N)" counters
    let bookCountBySeries: [Int32: Int]
    let booksByGenre: [Int16: [Int]]
    let bookCountByGenre: [Int16: Int]
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
        var bookIndex: [Int32: Book] = [:]
        bookIndex.reserveCapacity(books.count)
        for b in books where bookIndex[b.libid] == nil { bookIndex[b.libid] = b }
        self.bookByLibid = bookIndex
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
        self.bookCountByAuthor = byAuthor.mapValues(\.count)
        self.bookCountBySeries = bySeries.mapValues(\.count)
        self.bookCountByGenre = byGenre.mapValues(\.count)
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
    }
}
