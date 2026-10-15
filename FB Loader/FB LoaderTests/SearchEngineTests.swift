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
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
                Book(libid: 101, title: "Надежда Элантриса", authorIDs: [1],
                     seriesID: 1, seriesNum: 2, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
                Book(libid: 200, title: "Война и мир", authorIDs: [2],
                     seriesID: 2, seriesNum: 1, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
                Book(libid: 300, title: "Понедельник начинается в субботу", authorIDs: [3],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
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

    @Test("Кросс-токенный запрос «автор + серия» находит серию через расширенный ключ")
    func seriesByAuthorPlusSeries() {
        // Запрос «сандерсон элантрис»: авторские токены не содержат «элантрис»,
        // токены серии не содержат «сандерсон». Серия «Элантрис» должна
        // найтись благодаря searchKeySeriesExt — base series tokens + tokens
        // авторов её книг (Сандерсон).
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "сандерсон элантрис", language: "ru", in: lib)
        #expect(r.series.contains { lib.series[$0.seriesIndex].name == "Элантрис" },
                "ожидалось найти серию «Элантрис» по запросу «сандерсон элантрис»")
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
                     language: "en", archiveIndex: 0, size: 0, dateAdded: nil),
                Book(libid: 2, title: "Война и мир", authorIDs: [1],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
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
    private func book(_ libid: Int32, _ title: String, _ authorIDs: [Int32], series: Int32? = nil,
                      language: String = "ru") -> Book {
        Book(libid: libid, title: title, authorIDs: authorIDs, seriesID: series, seriesNum: nil,
             genreIDs: [], language: language, archiveIndex: 0, size: 0, dateAdded: nil)
    }

    private func library(authors: [Author], series: [Series] = [], books: [Book]) -> Library {
        Library(inpxHash: Data(repeating: 0xAB, count: 32), inpxVersion: "v", archives: ["arch"],
                authors: [Author.unknown] + authors, series: series, genres: [], books: books)
    }

    private let oldie = Author(id: 1, lastName: "Олди", firstName: "Генри", middleName: "Лайон")
    private let dyachenko = Author(id: 2, lastName: "Дяченко", firstName: "Марина", middleName: "")

    @Test("Соавтор (не первый) находит книгу по комбинированному ключу")
    func coAuthorFindsBook() {
        let lib = library(authors: [oldie, dyachenko], books: [book(1, "Рубеж", [1, 2])])
        let r = SearchEngine.run(query: "дяченко рубеж", language: "ru", in: lib)
        #expect(r.books.map { lib.books[$0.bookIndex].libid } == [1])
    }

    @Test("Соавтор (не первый) находит серию через расширенный ключ")
    func coAuthorFindsSeries() {
        let lib = library(authors: [oldie, dyachenko], series: [Series(id: 1, name: "Скитальцы")],
                          books: [book(1, "Ведьмак", [1, 2], series: 1)])
        let r = SearchEngine.run(query: "дяченко скитальцы", language: "ru", in: lib)
        #expect(r.series.map { lib.series[$0.seriesIndex].id } == [1])
    }

    @Test("Книга соавторов скрыта из бакета книг, когда сматчился второй автор")
    func coAuthorDedup() {
        let lib = library(authors: [oldie, dyachenko], books: [book(1, "Дяченко", [1, 2])])
        let r = SearchEngine.run(query: "дяченко", language: "ru", in: lib)
        #expect(r.authors.map { lib.authors[$0.authorIndex].id } == [2])
        #expect(r.books.isEmpty)
    }

    @Test("Украинская заглавная «І» находится строчным запросом")
    func ukrainianCapitalFound() {
        let lib = library(authors: [Author(id: 1, lastName: "Франко", firstName: "Іван", middleName: "")],
                          books: [book(1, "Захар Беркут", [1], language: "uk")])
        let r = SearchEngine.run(query: "іван", language: "uk", in: lib)
        #expect(r.authors.map { lib.authors[$0.authorIndex].id } == [1])
    }

    @Test("Автор и серия без книг на выбранном языке не попадают в выдачу")
    func authorsSeriesFilteredByLanguage() {
        let lib = library(authors: [Author(id: 1, lastName: "Tolstoy", firstName: "Leo", middleName: "")],
                          series: [Series(id: 1, name: "Tolstoy collection")],
                          books: [book(1, "War and peace", [1], series: 1, language: "en")])
        let ru = SearchEngine.run(query: "tolstoy", language: "ru", in: lib)
        #expect(ru.authors.isEmpty)
        #expect(ru.series.isEmpty)
        let en = SearchEngine.run(query: "tolstoy", language: "en", in: lib)
        #expect(en.authors.map { lib.authors[$0.authorIndex].id } == [1])
        #expect(en.series.map { lib.series[$0.seriesIndex].id } == [1])
    }

    @Test("Язык «не указан» находит авторов и серии книг с пустым языком")
    func unspecifiedLanguageAuthors() {
        let lib = library(authors: [Author(id: 1, lastName: "Tolstoy", firstName: "", middleName: "")],
                          series: [Series(id: 1, name: "Tolstoy collection")],
                          books: [book(1, "War", [1], series: 1, language: "")])
        let r = SearchEngine.run(query: "tolstoy", language: BooksByContext.unspecifiedLanguageToken, in: lib)
        #expect(r.authors.count == 1)
        #expect(r.series.count == 1)
    }

    @Test("Псевдо-автор «(Без автора)» не ищется, его книги не скрываются дедупом")
    func unknownAuthorNotSearchable() {
        let lib = library(authors: [], books: [book(1, "Без названия", [Author.unknownID])])
        let r = SearchEngine.run(query: "без", language: "ru", in: lib)
        #expect(r.authors.isEmpty)
        #expect(r.books.map { lib.books[$0.bookIndex].libid } == [1])
        let byName = SearchEngine.run(query: "без автора", language: "ru", in: lib)
        #expect(byName.authors.isEmpty)
        #expect(byName.books.isEmpty, "токены «(Без автора)» не должны попадать в ключ книги")
    }
}
