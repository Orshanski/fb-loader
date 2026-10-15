import Testing
import Foundation
@testable import FB_Loader

@Suite("ExportPlanner")
struct ExportPlannerTests {
    private func miniLibrary() -> Library {
        let authors = [
            Author.unknown,
            Author(id: 1, lastName: "Толстой", firstName: "Лев", middleName: "Николаевич"),
            Author(id: 2, lastName: "Дяченко", firstName: "Марина", middleName: ""),
            Author(id: 3, lastName: "Олди", firstName: "Генри", middleName: "Лайон"),
        ]
        let series = [Series(id: 1, name: "Серия/со/слешами")]
        let books = [
            Book(libid: 100, title: "Война: и мир", authorIDs: [1], seriesID: 1, seriesNum: 1,
                 genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
            Book(libid: 200, title: "Рубеж", authorIDs: [3, 2], seriesID: nil, seriesNum: nil,
                 genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
            Book(libid: 300, title: "Без авторов", authorIDs: [Author.unknownID],
                 seriesID: nil, seriesNum: nil, genreIDs: [], language: "ru",
                 archiveIndex: 0, size: 0, dateAdded: nil),
        ]
        return Library(inpxHash: Data(count: 32), inpxVersion: "v",
                       archives: ["lib"], authors: authors, series: series,
                       genres: [], books: books)
    }

    @Test("uses selected author when on Authors tab")
    func selectedAuthor() {
        let lib = miniLibrary()
        let plan = ExportPlanner.plan(libids: [200], rootFolder: FileManager.default.temporaryDirectory.appendingPathComponent("export"),
                                      selectedAuthorID: 2, selectedSeriesID: nil, in: lib)
        #expect(plan.first?.destination.path.hasSuffix("Дяченко Марина/Рубеж.fb2") ?? false)
    }

    @Test("uses first author when no author selected")
    func firstAuthorFallback() {
        let lib = miniLibrary()
        let plan = ExportPlanner.plan(libids: [200], rootFolder: FileManager.default.temporaryDirectory.appendingPathComponent("export"),
                                      selectedAuthorID: nil, selectedSeriesID: 1, in: lib)
        #expect(plan.first?.destination.path.hasSuffix("Олди Генри Лайон/Рубеж.fb2") ?? false)
    }

    @Test("books with no author go into '(Без автора)' folder")
    func unknownAuthor() {
        let lib = miniLibrary()
        let plan = ExportPlanner.plan(libids: [300], rootFolder: FileManager.default.temporaryDirectory.appendingPathComponent("export"),
                                      selectedAuthorID: nil, selectedSeriesID: nil, in: lib)
        #expect(plan.first?.destination.path.hasSuffix("(Без автора)/Без авторов.fb2") ?? false)
    }

    @Test("forbidden filename characters are replaced with underscore")
    func sanitization() {
        let lib = miniLibrary()
        let plan = ExportPlanner.plan(libids: [100], rootFolder: FileManager.default.temporaryDirectory.appendingPathComponent("export"),
                                      selectedAuthorID: 1, selectedSeriesID: nil, in: lib)
        let path = plan.first!.destination.path
        let filename = (path as NSString).lastPathComponent
        #expect(!filename.contains(":"))
        #expect(filename.contains("Война_ и мир"))
    }

    private func library(titles: [(libid: Int32, title: String, archive: Int16)],
                         authorName: String = "Толстой") -> Library {
        let authors = [Author.unknown, Author(id: 1, lastName: authorName, firstName: "", middleName: "")]
        let books = titles.map {
            Book(libid: $0.libid, title: $0.title, authorIDs: [1], seriesID: nil, seriesNum: nil,
                 genreIDs: [], language: "ru", archiveIndex: $0.archive, size: 0, dateAdded: nil)
        }
        return Library(inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a", "b"],
                       authors: authors, series: [], genres: [], books: books)
    }

    private let root = URL(fileURLWithPath: "/export", isDirectory: true)

    private func names(_ plan: [ExportItem]) -> [String] {
        plan.map { $0.destination.lastPathComponent }
    }

    @Test("длинное кириллическое название укладывается в 255 байт без разрыва графем")
    func longCyrillicTitleFitsByteLimit() {
        let title = String(repeating: "й", count: 150) + String(repeating: "ё\u{0301}", count: 50)
        let plan = ExportPlanner.plan(libids: [1], rootFolder: root, selectedAuthorID: nil,
                                      selectedSeriesID: nil, in: library(titles: [(1, title, 0)]))
        let name = plan[0].destination.lastPathComponent
        #expect(name.hasSuffix(".fb2"))
        #expect(name.decomposedStringWithCanonicalMapping.utf8.count <= 255)
        #expect(title.hasPrefix(String(name.dropLast(4))))
    }

    @Test("длинное имя автора укладывается в 255 байт")
    func longAuthorFitsByteLimit() {
        let plan = ExportPlanner.plan(libids: [1], rootFolder: root, selectedAuthorID: nil, selectedSeriesID: nil,
                                      in: library(titles: [(1, "Т", 0)], authorName: String(repeating: "Щ", count: 300)))
        let folder = plan[0].destination.deletingLastPathComponent().lastPathComponent
        #expect(folder.decomposedStringWithCanonicalMapping.utf8.count <= 255)
        #expect(folder.hasPrefix("ЩЩЩ"))
    }

    @Test("ведущая точка, пустое имя и «..» не дают скрытых и выходящих за корень имён",
          arguments: [(".hidden", "_hidden.fb2"), ("", "_.fb2"), ("..", "__.fb2"),
                      ("  .  ", "_.fb2"), ("../etc", "___etc.fb2"), ("a\u{0}b\nc", "a_b_c.fb2"),
                      ("a\u{202E}b\u{200B}c\u{2028}d", "a_b_c_d.fb2")])
    func hiddenAndEscapingTitles(title: String, expected: String) {
        let plan = ExportPlanner.plan(libids: [1], rootFolder: root, selectedAuthorID: nil,
                                      selectedSeriesID: nil, in: library(titles: [(1, title, 0)]))
        #expect(names(plan) == [expected])
    }

    @Test("папка «..» и пустая папка остаются внутри корня",
          arguments: [("..", "__"), ("", "(Без автора)"), (".", "_")])
    func escapingFolder(author: String, expected: String) {
        let plan = ExportPlanner.plan(libids: [1], rootFolder: root, selectedAuthorID: nil, selectedSeriesID: nil,
                                      in: library(titles: [(1, "Т", 0)], authorName: author))
        let folder = plan[0].destination.deletingLastPathComponent()
        #expect(folder.lastPathComponent == expected)
        #expect(folder.deletingLastPathComponent().standardizedFileURL.path == "/export")
    }

    @Test("совпадающие имена получают суффиксы, регистр не различается, порядок по архиву и libid")
    func collisions() {
        let lib = library(titles: [(30, "Война и мир", 0), (10, "ВОЙНА И МИР", 1),
                                   (20, "война и мир", 0), (40, "Анна", 0)])
        for _ in 0..<5 {
            let plan = ExportPlanner.plan(libids: [10, 20, 30, 40], rootFolder: root, selectedAuthorID: nil,
                                          selectedSeriesID: nil, in: lib)
            #expect(plan.map(\.book.libid) == [20, 30, 40, 10])
            #expect(names(plan) == ["война и мир.fb2", "Война и мир (2).fb2", "Анна.fb2", "ВОЙНА И МИР (3).fb2"])
        }
    }

    @Test("суффикс не совпадает с натуральным именем другой книги")
    func suffixDoesNotOverwriteNaturalName() {
        let plan = ExportPlanner.plan(libids: [1, 2, 3], rootFolder: root, selectedAuthorID: nil, selectedSeriesID: nil,
                                      in: library(titles: [(1, "А", 0), (2, "А", 0), (3, "А (2)", 0)]))
        #expect(Set(plan.map(\.destination)).count == 3)
        #expect(names(plan) == ["А.fb2", "А (2).fb2", "А (2) (2).fb2"])
    }

    @Test("синглтоны вне NFD (U+212A) считаются по фактическим байтам")
    func singletonByteCount() {
        let plan = ExportPlanner.plan(libids: [1], rootFolder: root, selectedAuthorID: nil, selectedSeriesID: nil,
                                      in: library(titles: [(1, String(repeating: "\u{212A}", count: 100), 0)]))
        #expect(plan[0].destination.lastPathComponent.utf8.count <= 255)
    }

    @Test("суффикс коллизии не выводит имя за лимит байт")
    func collisionSuffixRespectsByteLimit() {
        let title = String(repeating: "ж", count: 200)
        let plan = ExportPlanner.plan(libids: [1, 2], rootFolder: root, selectedAuthorID: nil, selectedSeriesID: nil,
                                      in: library(titles: [(1, title, 0), (2, title, 0)]))
        let second = plan[1].destination.lastPathComponent
        #expect(second.hasSuffix(" (2).fb2"))
        #expect(second.utf8.count <= 255)
        #expect(plan[0].destination != plan[1].destination)
    }
}
