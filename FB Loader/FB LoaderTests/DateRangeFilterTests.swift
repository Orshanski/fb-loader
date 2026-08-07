import Foundation
import Testing
@testable import FB_Loader

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
}

private func book(_ libid: Int32, added: Date?, language: String = "ru") -> Book {
    Book(libid: libid, title: "T", authorIDs: [1], seriesID: nil, seriesNum: nil,
         genreIDs: [], language: language, archiveIndex: 0, size: 0,
         dateAdded: added)
}

@Suite("DateRangeFilter")
struct DateRangeFilterTests {
    private let filter = DateRangeFilter(from: day(2013, 3, 1), to: day(2015, 6, 30))

    @Test("нижняя граница включительно")
    func lowerBoundInclusive() {
        #expect(filter.contains(book(1, added: day(2013, 3, 1))))
        #expect(!filter.contains(book(2, added: day(2013, 2, 28))))
    }

    @Test("верхняя граница включительно")
    func upperBoundInclusive() {
        #expect(filter.contains(book(3, added: day(2015, 6, 30))))
        #expect(!filter.contains(book(4, added: day(2015, 7, 1))))
    }

    @Test("книга без даты не проходит")
    func missingDateExcluded() {
        #expect(!filter.contains(book(5, added: nil)))
    }

    @Test("перевёрнутый диапазон не пропускает никого")
    func invertedRangeEmpty() {
        let inverted = DateRangeFilter(from: day(2015, 6, 30), to: day(2013, 3, 1))
        #expect(!inverted.contains(book(6, added: day(2014, 1, 1))))
    }
}

@Suite("BooksByContext — даты")
struct BooksByContextDateTests {
    private func library() -> Library {
        Library(
            inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
            authors: [Author(id: 1, lastName: "X", firstName: "", middleName: "")],
            series: [], genres: [],
            books: [
                book(1, added: day(2012, 12, 31)),
                book(2, added: day(2013, 3, 1)),
                book(3, added: day(2015, 6, 30)),
                book(4, added: day(2016, 1, 1)),
                book(5, added: day(2014, 1, 1), language: "en"),
            ])
    }

    @Test("без дат — поведение прежнее, только по языку")
    func noDatesUnchanged() {
        let lib = library()
        let r = BooksByContext.books(for: .author(1), language: "ru", in: lib)
        #expect(r.map(\.libid) == [1, 2, 3, 4])
    }

    @Test("диапазон отсекает по краям включительно")
    func rangeInclusive() {
        let lib = library()
        let r = BooksByContext.books(
            for: .author(1), language: "ru",
            dates: DateRangeFilter(from: day(2013, 3, 1), to: day(2015, 6, 30)),
            in: lib)
        #expect(r.map(\.libid) == [2, 3])
    }

    @Test("диапазон комбинируется с языком")
    func rangeAndLanguage() {
        let lib = library()
        let r = BooksByContext.books(
            for: .author(1), language: "en",
            dates: DateRangeFilter(from: day(2013, 1, 1), to: day(2015, 1, 1)),
            in: lib)
        #expect(r.map(\.libid) == [5])
    }

    @Test("знаменатель игнорирует даты, но учитывает язык")
    func totalIgnoresDates() {
        let lib = library()
        let filtered = BooksByContext.booksWithTotal(
            for: .author(1), language: "ru",
            dates: DateRangeFilter(from: day(2013, 3, 1), to: day(2015, 6, 30)),
            in: lib)
        #expect(filtered.books.count == 2)
        #expect(filtered.total == 4)

        let en = BooksByContext.booksWithTotal(
            for: .author(1), language: "en", dates: nil, in: lib)
        #expect(en.total == 1)
    }
}
