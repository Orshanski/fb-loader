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
                 genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            Book(libid: 200, title: "Рубеж", authorIDs: [3, 2], seriesID: nil, seriesNum: nil,
                 genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            Book(libid: 300, title: "Без авторов", authorIDs: [Author.unknownID],
                 seriesID: nil, seriesNum: nil, genreIDs: [], language: "ru",
                 archiveIndex: 0, size: 0, dateAddedDays: 0),
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
}
