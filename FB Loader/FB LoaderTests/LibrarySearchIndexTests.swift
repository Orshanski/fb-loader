import Testing
import Foundation
@testable import FB_Loader

@Suite("Library search index")
struct LibrarySearchIndexTests {
    private func authorIndices(ofBook i: Int, in lib: Library) -> [Int32] {
        Array(lib.bookAuthorIndices[Int(lib.bookAuthorStarts[i])..<Int(lib.bookAuthorStarts[i + 1])])
    }

    private func decode(_ key: [[UInt32]]) -> [String] {
        key.map { String(String.UnicodeScalarView($0.compactMap { Unicode.Scalar($0) })) }
    }

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
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
            ]
        )

        #expect(lib.searchKeyAuthors.count == lib.authors.count)
        #expect(lib.searchKeySeries.count == lib.series.count)
        #expect(lib.searchKeyTitle.count == lib.books.count)
        #expect(lib.bookAuthorStarts.count == lib.books.count + 1)
        #expect(lib.searchSeriesIdx.count == lib.books.count)

        let sandersonTokens = lib.searchKeyAuthors[1]
        #expect(sandersonTokens.count == 2)

        // У книги Элантрис автор Сандерсон (id=1, index=1) и серия Элантрис (id=1, index=0)
        #expect(authorIndices(ofBook: 0, in: lib) == [1])
        #expect(lib.searchSeriesIdx[0] == 0)

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
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
            ]
        )
        #expect(lib.searchSeriesIdx[0] == -1)
    }

    @Test("Все авторы книги попадают в её индексы; отсутствующие и «(Без автора)» пропускаются")
    func bookAuthorIndicesAllAuthors() {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [
                Author.unknown,
                Author(id: 1, lastName: "Олди", firstName: "Генри", middleName: ""),
                Author(id: 2, lastName: "Дяченко", firstName: "Марина", middleName: ""),
            ],
            series: [], genres: [],
            books: [
                Book(libid: 100, title: "Рубеж", authorIDs: [1, 999, 2],   // 999 нет в authors
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
                Book(libid: 101, title: "Аноним", authorIDs: [Author.unknownID],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
                Book(libid: 102, title: "Orphan", authorIDs: [999],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
            ]
        )
        #expect(authorIndices(ofBook: 0, in: lib) == [1, 2])
        #expect(authorIndices(ofBook: 1, in: lib) == [])
        #expect(authorIndices(ofBook: 2, in: lib) == [])
    }

    @Test("Расширенный ключ серии содержит токены всех соавторов, но не «(Без автора)»")
    func seriesExtKeyAllCoAuthors() {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [
                Author.unknown,
                Author(id: 1, lastName: "Олди", firstName: "", middleName: ""),
                Author(id: 2, lastName: "Дяченко", firstName: "", middleName: ""),
            ],
            series: [Series(id: 1, name: "Рубеж")],
            genres: [],
            books: [
                Book(libid: 100, title: "Рубеж", authorIDs: [1, 2],
                     seriesID: 1, seriesNum: 1, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
                Book(libid: 101, title: "Приложение", authorIDs: [Author.unknownID],
                     seriesID: 1, seriesNum: 2, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
            ]
        )
        #expect(Set(decode(lib.searchKeySeriesExt[0])) == ["рубеж", "олди", "дяченко"])
    }

    @Test("Псевдо-автор «(Без автора)» имеет пустой search-ключ")
    func unknownAuthorEmptyKey() {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"], authors: [Author.unknown], series: [], genres: [], books: []
        )
        #expect(lib.searchKeyAuthors[0].isEmpty)
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
