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
}
