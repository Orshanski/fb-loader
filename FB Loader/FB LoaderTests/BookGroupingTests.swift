import Testing
import Foundation
@testable import FB_Loader

@Suite("BookGrouping")
struct BookGroupingTests {
    private func book(_ libid: Int32, series: Int32? = nil, num: Int16? = nil) -> Book {
        Book(libid: libid, title: "B\(libid)", authorIDs: [1], seriesID: series, seriesNum: num,
             genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAdded: nil)
    }

    private func library(_ series: [Series]) -> Library {
        Library(inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
                authors: [Author(id: 1, lastName: "X", firstName: "", middleName: "")],
                series: series, genres: [], books: [])
    }

    @Test("книги вне серий — в порядке выборки, серии по имени, книги серии по номеру")
    func groups() {
        let lib = library([Series(id: 1, name: "Б"), Series(id: 2, name: "А")])
        let g = BookGrouping.group(
            [book(1), book(2, series: 1, num: 2), book(3, series: 2, num: 1),
             book(4, series: 1, num: 1), book(5)],
            library: lib)
        #expect(g.loose.map(\.libid) == [1, 5])
        #expect(g.series.map(\.series.name) == ["А", "Б"])
        #expect(g.series[1].books.map(\.libid) == [4, 2])
    }

    @Test("равные номера и без номера — в порядке выборки, без номера в конце")
    func stableTies() {
        let lib = library([Series(id: 1, name: "S")])
        let g = BookGrouping.group(
            [book(1, series: 1), book(2, series: 1, num: 1), book(3, series: 1, num: 1)],
            library: lib)
        #expect(g.series[0].books.map(\.libid) == [2, 3, 1])
    }

    @Test("серия, которой нет в библиотеке, получает имя «?»")
    func unknownSeries() {
        let g = BookGrouping.group([book(1, series: 9)], library: library([]))
        #expect(g.series.map(\.series.name) == ["?"])
    }
}

@Suite("RussianPlural")
struct RussianPluralTests {
    @Test("склонение «книга/книги/книг»", arguments: [
        (1, "1 книга"), (2, "2 книги"), (5, "5 книг"), (11, "11 книг"), (12, "12 книг"),
        (14, "14 книг"), (21, "21 книга"), (22, "22 книги"), (25, "25 книг"),
        (101, "101 книга"), (111, "111 книг"), (0, "0 книг"),
    ])
    func books(n: Int, expected: String) {
        #expect(booksCountLabel(n) == expected)
    }
}
