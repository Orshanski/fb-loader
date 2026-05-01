import Testing
import Foundation
@testable import FB_Loader

@Suite("INPXImporter")
struct INPXImporterTests {
    @Test("parses tiny.inpx into expected catalog")
    func parsesTiny() throws {
        let url = try #require(Bundle(for: TinyAnchor.self)
            .url(forResource: "tiny", withExtension: "inpx"))
        let dict = try GenreDictionary.loadFromBundle()
        let lib = try INPXImporter.import_(inpxURL: url, genres: dict)
        #expect(lib.books.count == 2)
        #expect(lib.archives == ["lib-001"])
        #expect(lib.inpxVersion == "20260301")

        // Authors: Толстой + Дяченко(М) + Дяченко(С) + Олди = 4 (or 3 if Дяченки dedup —
        // they are different middleNames, so distinct → 4).
        #expect(lib.authors.count == 4)
        // Series: "Великие романы" + "Большая серия" = 2.
        #expect(lib.series.count == 2)

        let bookByLibid = Dictionary(uniqueKeysWithValues: lib.books.map { ($0.libid, $0) })
        let warAndPeace = try #require(bookByLibid[100001])
        #expect(warAndPeace.title == "Война и мир")
        #expect(warAndPeace.authorIDs.count == 1)

        let rubezh = try #require(bookByLibid[200001])
        #expect(rubezh.title == "Рубеж. Пентакль")
        #expect(rubezh.authorIDs.count == 3)
        #expect(rubezh.size == 6400838)
    }
}

/// Anchor type used to locate the test bundle resources.
private final class TinyAnchor {}
