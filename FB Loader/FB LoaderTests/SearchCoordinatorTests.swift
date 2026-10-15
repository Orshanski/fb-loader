import Testing
import Foundation
@testable import FB_Loader

@Suite("SearchCoordinator")
@MainActor
struct SearchCoordinatorTests {
    private func makeLibrary() -> Library {
        Library(
            inpxHash: Data(repeating: 0xAB, count: 32), inpxVersion: "v", archives: ["arch"],
            authors: [Author.unknown, Author(id: 1, lastName: "Толстой", firstName: "Лев", middleName: "")],
            series: [], genres: [],
            books: [Book(libid: 1, title: "Война и мир", authorIDs: [1], seriesID: nil, seriesNum: nil,
                         genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAdded: nil)]
        )
    }

    @Test("Смена языка после поиска сбрасывает результаты")
    func languageChangeClearsResults() async {
        let coord = SearchCoordinator(initialLanguage: "ru")
        coord.query = "толстой"
        await coord.runSearch(in: makeLibrary())
        #expect(coord.results?.authors.count == 1)
        coord.selectedBookLibid = 1

        coord.languageFilter = "en"
        #expect(coord.results == nil)
        #expect(coord.lastQuery == "")
        #expect(coord.selectedBookLibid == nil)
        #expect(coord.query == "толстой", "текст запроса остаётся для повторного поиска")
    }

    @Test("Присвоение того же языка результаты не сбрасывает")
    func sameLanguageKeepsResults() async {
        let coord = SearchCoordinator(initialLanguage: "ru")
        coord.query = "толстой"
        await coord.runSearch(in: makeLibrary())
        coord.languageFilter = "ru"
        #expect(coord.results != nil)
    }
}
