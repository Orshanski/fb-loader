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
}
