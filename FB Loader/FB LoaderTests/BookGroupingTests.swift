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
