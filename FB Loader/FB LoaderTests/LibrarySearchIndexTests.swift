import Testing
import Foundation
@testable import FB_Loader

@Suite("Library search index")
struct LibrarySearchIndexTests {
    @Test("Library.init строит search-ключи параллельно authors/series/books")
    func searchIndicesBuilt() {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [
                Author.unknown,
                Author(id: 1, lastName: "Сандерсон", firstName: "Брэндон", middleName: ""),
            ],
            series: [Series(id: 1, name: "Элантрис")],
            genres: [],
            books: [
                Book(libid: 100, title: "Элантрис", authorIDs: [1],
                     seriesID: 1, seriesNum: 1, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            ]
        )

        #expect(lib.searchKeyAuthors.count == lib.authors.count)
        #expect(lib.searchKeySeries.count == lib.series.count)
        #expect(lib.searchKeyTitle.count == lib.books.count)
        #expect(lib.searchAuthorIdx.count == lib.books.count)
        #expect(lib.searchSeriesIdx.count == lib.books.count)

        // Сандерсон → автор index 1 → токены ["сандерсон", "брэндон"]
        let sandersonTokens = lib.searchKeyAuthors[1]
        #expect(sandersonTokens.count == 2)

        // У книги Элантрис автор Сандерсон (id=1, index=1) и серия Элантрис (id=1, index=0)
        #expect(lib.searchAuthorIdx[0] == 1)
        #expect(lib.searchSeriesIdx[0] == 0)

        // Title key токенизирован
        #expect(lib.searchKeyTitle[0].count == 1)  // одно слово "элантрис"
    }

    @Test("Книга без серии → searchSeriesIdx == -1")
    func searchSeriesIdxNilSentinel() {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"], authors: [Author.unknown], series: [], genres: [],
            books: [
                Book(libid: 100, title: "Sample", authorIDs: [Author.unknownID],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            ]
        )
        #expect(lib.searchSeriesIdx[0] == -1)
    }

    @Test("Книга, чей primary autorID отсутствует среди authors → searchAuthorIdx == -1")
    func searchAuthorIdxMissingSentinel() {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [Author.unknown],   // только unknownID=0
            series: [], genres: [],
            books: [
                Book(libid: 100, title: "Orphan", authorIDs: [999],   // ID нет в authors
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            ]
        )
        #expect(lib.searchAuthorIdx[0] == -1)
    }

    @Test("ё/Ё в имени автора нормализуется в search-ключе")
    func searchKeyAuthorsNormalisesYo() {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [
                Author.unknown,
                Author(id: 1, lastName: "Алёшин", firstName: "Ёж", middleName: ""),
            ],
            series: [], genres: [], books: []
        )
        // displayName = "Алёшин Ёж" → preprocess → ["алешин", "еж"]
        let toks = lib.searchKeyAuthors[1]
        #expect(toks.count == 2)
        let decoded = toks.map {
            String(String.UnicodeScalarView($0.compactMap { Unicode.Scalar($0) }))
        }
        #expect(decoded == ["алешин", "еж"])
    }
}
