import Testing
import Foundation
@testable import FB_Loader

@Suite("SearchEngine")
struct SearchEngineTests {
    private func makeLibrary() -> Library {
        Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [
                Author.unknown,
                Author(id: 1, lastName: "Сандерсон", firstName: "Брэндон", middleName: ""),
                Author(id: 2, lastName: "Толстой", firstName: "Лев", middleName: "Николаевич"),
                Author(id: 3, lastName: "Стругацкий", firstName: "Аркадий", middleName: ""),
            ],
            series: [
                Series(id: 1, name: "Элантрис"),
                Series(id: 2, name: "Война и мир"),
            ],
            genres: [],
            books: [
                Book(libid: 100, title: "Элантрис", authorIDs: [1],
                     seriesID: 1, seriesNum: 1, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
                Book(libid: 101, title: "Надежда Элантриса", authorIDs: [1],
                     seriesID: 1, seriesNum: 2, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
                Book(libid: 200, title: "Война и мир", authorIDs: [2],
                     seriesID: 2, seriesNum: 1, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
                Book(libid: 300, title: "Понедельник начинается в субботу", authorIDs: [3],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            ]
        )
    }

    @Test("Точный запрос по имени автора находит автора")
    func authorExactMatch() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "Сандерсон", language: "ru", in: lib)
        #expect(r.authors.contains { lib.authors[$0.authorIndex].lastName == "Сандерсон" })
    }

    @Test("Запрос по имени автора НЕ дублирует его книги в bucket'е")
    func authorMatchDoesNotPopulateBookBucket() {
        // Регрессионный тест: книжный бакет матчит только по title-токенам.
        // Книги, попадающие в выдачу через автора, видны в блоке автора —
        // здесь не дублируем.
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "Сандерсон", language: "ru", in: lib)
        let bookTitles = r.books.map { lib.books[$0.bookIndex].title }
        #expect(!bookTitles.contains("Элантрис"),
                "«Элантрис» не должна быть в book-bucket по запросу 'Сандерсон'")
        #expect(!bookTitles.contains("Надежда Элантриса"),
                "«Надежда Элантриса» не должна быть в book-bucket по запросу 'Сандерсон'")
    }

    @Test("Опечатка в имени автора (1 символ) — всё ещё находит")
    func authorTypo() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "сандерсн", language: "ru", in: lib)
        #expect(r.authors.contains { lib.authors[$0.authorIndex].lastName == "Сандерсон" })
    }

    @Test("Запрос по серии находит серию")
    func seriesMatch() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "Элантрис", language: "ru", in: lib)
        #expect(r.series.contains { lib.series[$0.seriesIndex].name == "Элантрис" })
    }

    @Test("Многословный запрос по книге находит книгу")
    func multiTokenBook() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "понедельник субботу", language: "ru", in: lib)
        #expect(r.books.contains { lib.books[$0.bookIndex].title.contains("Понедельник") })
    }

    @Test("Языковой фильтр исключает книги другого языка из бакета")
    func languageFilter() {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [Author.unknown,
                      Author(id: 1, lastName: "Tolstoy", firstName: "Leo", middleName: "")],
            series: [], genres: [],
            books: [
                Book(libid: 1, title: "War and peace", authorIDs: [1],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "en", archiveIndex: 0, size: 0, dateAddedDays: 0),
                Book(libid: 2, title: "Война и мир", authorIDs: [1],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            ]
        )
        let r = SearchEngine.run(query: "война мир", language: "ru", in: lib)
        for m in r.books {
            #expect(lib.books[m.bookIndex].language == "ru")
        }
    }

    @Test("Скоры отсортированы по убыванию во всех бакетах")
    func sortedDescending() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "Элантрис", language: "ru", in: lib)
        #expect(r.books == r.books.sorted { $0.score > $1.score })
        #expect(r.authors == r.authors.sorted { $0.score > $1.score })
        #expect(r.series == r.series.sorted { $0.score > $1.score })
    }

    @Test("Пустой запрос возвращает пустой результат")
    func emptyQuery() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "   ", language: "ru", in: lib)
        #expect(r.authors.isEmpty)
        #expect(r.series.isEmpty)
        #expect(r.books.isEmpty)
    }
}
