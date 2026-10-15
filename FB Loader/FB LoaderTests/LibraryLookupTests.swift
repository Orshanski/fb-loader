import Testing
import Foundation
@testable import FB_Loader

@Suite("Library — поиск книги по libid")
struct LibraryLookupTests {
    private static func book(_ libid: Int32, _ title: String) -> Book {
        Book(libid: libid, title: title, authorIDs: [Author.unknownID], seriesID: nil, seriesNum: nil,
             genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAdded: nil)
    }

    private let lib: Library

    init() {
        lib = Library(inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
                      authors: [Author.unknown], series: [], genres: [],
                      books: [Self.book(7, "Первая"), Self.book(3, "Вторая"), Self.book(7, "Повтор")])
    }

    @Test("находит книгу по libid")
    func found() {
        #expect(lib.book(libid: 3)?.title == "Вторая")
    }

    @Test("незнакомый libid — nil")
    func missing() {
        #expect(lib.book(libid: 99) == nil)
    }

    @Test("повтор libid — первая книга")
    func duplicateKeepsFirst() {
        #expect(lib.book(libid: 7)?.title == "Первая")
    }

    @Test("автор и серия по id")
    func authorAndSeries() {
        let a = Author(id: 42, lastName: "Толстой", firstName: "Лев", middleName: "")
        let lib = Library(inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
                          authors: [Author.unknown, a], series: [Series(id: 5, name: "С")], genres: [],
                          books: [])
        #expect(lib.author(id: 42)?.lastName == "Толстой")
        #expect(lib.author(id: 7) == nil)
        #expect(lib.series(id: 5)?.name == "С")
        #expect(lib.series(id: 6) == nil)
    }
}

@Suite("Library — книги по языкам")
struct LibraryLanguageCountTests {
    private static func book(_ libid: Int32, authors: [Int32], series: Int32?, lang: String) -> Book {
        Book(libid: libid, title: "t", authorIDs: authors, seriesID: series, seriesNum: nil,
             genreIDs: [], language: lang, archiveIndex: 0, size: 0, dateAdded: nil)
    }

    private let lib = Library(
        inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
        authors: [Author.unknown,
                  Author(id: 1, lastName: "А", firstName: "", middleName: ""),
                  Author(id: 2, lastName: "Б", firstName: "", middleName: "")],
        series: [Series(id: 9, name: "С")], genres: [],
        books: [book(1, authors: [1], series: 9, lang: "ru"),
                book(2, authors: [1, 2], series: 9, lang: "ru"),
                book(3, authors: [1], series: nil, lang: "en"),
                book(4, authors: [2], series: 9, lang: "")])

    @Test("автор: по каждому языку отдельно")
    func authorCounts() {
        #expect(lib.bookCount(authorID: 1, language: "ru") == 2)
        #expect(lib.bookCount(authorID: 1, language: "en") == 1)
        #expect(lib.bookCount(authorID: 1, language: "") == 0)
        #expect(lib.bookCount(authorID: 2, language: "ru") == 1)
        #expect(lib.bookCount(authorID: 2, language: "") == 1)
    }

    @Test("серия: по каждому языку отдельно")
    func seriesCounts() {
        #expect(lib.bookCount(seriesID: 9, language: "ru") == 2)
        #expect(lib.bookCount(seriesID: 9, language: "") == 1)
        #expect(lib.bookCount(seriesID: 9, language: "en") == 0)
    }

    @Test("незнакомые id и язык — ноль")
    func unknown() {
        #expect(lib.bookCount(authorID: 99, language: "ru") == 0)
        #expect(lib.bookCount(seriesID: 99, language: "ru") == 0)
        #expect(lib.bookCount(authorID: 1, language: "de") == 0)
    }
}
