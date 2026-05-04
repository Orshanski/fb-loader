import Testing
import Foundation
@testable import FB_Loader

@Suite("BooksByContext")
struct BooksByContextTests {
    private func buildLibrary() -> Library {
        let books = [
            Book(libid: 1, title: "A", authorIDs: [1], seriesID: nil, seriesNum: nil,
                 genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            Book(libid: 2, title: "B", authorIDs: [1, 2], seriesID: 1, seriesNum: 1,
                 genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            Book(libid: 3, title: "C", authorIDs: [2], seriesID: 1, seriesNum: 2,
                 genreIDs: [], language: "en", archiveIndex: 0, size: 0, dateAddedDays: 0),
        ]
        return Library(
            inpxHash: Data(count: 32), inpxVersion: "v",
            archives: ["a"], authors: [
                Author.unknown,
                Author(id: 1, lastName: "X", firstName: "", middleName: ""),
                Author(id: 2, lastName: "Y", firstName: "", middleName: ""),
            ],
            series: [Series(id: 1, name: "S1")],
            genres: [], books: books)
    }

    @Test("for an author, returns ALL books where author is mentioned")
    func authorIncludesCoauthored() {
        let lib = buildLibrary()
        let r = BooksByContext.books(for: .author(1), language: "ru", in: lib)
        #expect(r.map(\.libid) == [1, 2])
    }

    @Test("for a series, returns books in that series")
    func series() {
        let lib = buildLibrary()
        let r = BooksByContext.books(for: .series(1), language: "ru", in: lib)
        #expect(r.map(\.libid) == [2])
    }

    @Test("language filter applies")
    func language() {
        let lib = buildLibrary()
        let r = BooksByContext.books(for: .author(2), language: "en", in: lib)
        #expect(r.map(\.libid) == [3])
    }

    @Test("'Не указан' matches empty language")
    func unknownLanguage() {
        let lib = Library(
            inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
            authors: [Author(id: 1, lastName: "X", firstName: "", middleName: "")],
            series: [], genres: [],
            books: [Book(libid: 9, title: "?", authorIDs: [1], seriesID: nil,
                         seriesNum: nil, genreIDs: [], language: "",
                         archiveIndex: 0, size: 0, dateAddedDays: 0)])
        let r = BooksByContext.books(for: .author(1),
                                     language: BooksByContext.unspecifiedLanguageToken,
                                     in: lib)
        #expect(r.map(\.libid) == [9])
    }

    @Test("library builds genre indices and language-aware counts")
    func genreIndices() {
        let genres = [
            Genre(id: 1, code: "", name: "Фантастика", parentID: nil),
            Genre(id: 100, code: "sf", name: "Научная фантастика", parentID: 1),
            Genre(id: 101, code: "sf_fantasy", name: "Фэнтези", parentID: 1),
            Genre(id: 1001, code: "sf_deep", name: "Поджанр НФ", parentID: 100),
            Genre(id: 9000, code: "orphan", name: "Без родителя", parentID: 999),
        ]
        let books = [
            Book(libid: 10, title: "Root", authorIDs: [1], seriesID: nil,
                 seriesNum: nil, genreIDs: [1], language: "ru",
                 archiveIndex: 0, size: 0, dateAddedDays: 0),
            Book(libid: 11, title: "SF RU", authorIDs: [1], seriesID: nil,
                 seriesNum: nil, genreIDs: [100], language: "ru",
                 archiveIndex: 0, size: 0, dateAddedDays: 0),
            Book(libid: 12, title: "SF EN", authorIDs: [1], seriesID: nil,
                 seriesNum: nil, genreIDs: [100], language: "en",
                 archiveIndex: 0, size: 0, dateAddedDays: 0),
            Book(libid: 13, title: "Both", authorIDs: [1], seriesID: nil,
                 seriesNum: nil, genreIDs: [100, 101], language: "ru",
                 archiveIndex: 0, size: 0, dateAddedDays: 0),
        ]
        let lib = Library(
            inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
            authors: [Author(id: 1, lastName: "A", firstName: "", middleName: "")],
            series: [], genres: genres, books: books)

        #expect(lib.rootGenres.map(\.id) == [1])
        #expect(lib.childGenresByParent[1]?.map(\.id) == [100, 101, 1001])
        #expect(lib.orphanGenres.map(\.id) == [9000])
        #expect(lib.sidebarGenres.map(\.id) == [1, 100, 101, 1001, 9000])
        #expect(lib.lowercasedSidebarGenreNames == [
            "фантастика", "научная фантастика", "фэнтези", "поджанр нф", "без родителя",
        ])
        #expect(lib.booksByGenre[1] == [0])
        #expect(lib.booksByGenre[100] == [1, 2, 3])
        #expect(lib.bookCountByGenreByLang[100]?["ru"] == 2)
        #expect(lib.bookCountByGenreByLang[100]?["en"] == 1)
        #expect(lib.bookCountByGenreByLang[101]?["en"] == nil)
    }

    @Test("genre context returns exact genre matches and respects language")
    func genreContextExactLanguage() {
        let lib = Library(
            inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
            authors: [Author(id: 1, lastName: "A", firstName: "", middleName: "")],
            series: [],
            genres: [
                Genre(id: 1, code: "", name: "Фантастика", parentID: nil),
                Genre(id: 100, code: "sf", name: "Научная фантастика", parentID: 1),
            ],
            books: [
                Book(libid: 20, title: "Root", authorIDs: [1], seriesID: nil,
                     seriesNum: nil, genreIDs: [1], language: "ru",
                     archiveIndex: 0, size: 0, dateAddedDays: 0),
                Book(libid: 21, title: "Child RU", authorIDs: [1], seriesID: nil,
                     seriesNum: nil, genreIDs: [100], language: "ru",
                     archiveIndex: 0, size: 0, dateAddedDays: 0),
                Book(libid: 22, title: "Child EN", authorIDs: [1], seriesID: nil,
                     seriesNum: nil, genreIDs: [100], language: "en",
                     archiveIndex: 0, size: 0, dateAddedDays: 0),
            ])

        #expect(BooksByContext.books(for: .genre(1), language: "ru", in: lib).map(\.libid) == [20])
        #expect(BooksByContext.books(for: .genre(100), language: "ru", in: lib).map(\.libid) == [21])
        #expect(BooksByContext.books(for: .genre(100), language: "en", in: lib).map(\.libid) == [22])
    }
}
