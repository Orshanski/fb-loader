import Testing
import Foundation
@testable import FB_Loader

@Suite("LibraryBinaryCodec")
struct LibraryBinaryCodecTests {
    @Test("encode then decode produces the same library")
    func roundTrip() throws {
        let original = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "20260301",
            archives: ["lib-001", "lib-002"],
            authors: [
                Author.unknown,
                Author(id: 1, lastName: "Толстой", firstName: "Лев", middleName: "Николаевич"),
            ],
            series: [Series(id: 1, name: "Великие романы")],
            genres: [Genre(id: 1, code: "prose_classic", name: "Классическая проза", parentID: nil)],
            books: [
                Book(libid: 100001, title: "Война и мир", authorIDs: [1],
                     seriesID: 1, seriesNum: 1, genreIDs: [1],
                     language: "ru", archiveIndex: 0, size: 987654, dateAddedDays: 4000),
            ]
        )
        let data = try LibraryBinaryCodec.encode(original)
        let decoded = try LibraryBinaryCodec.decode(data)
        #expect(decoded.inpxVersion == "20260301")
        #expect(decoded.archives == ["lib-001", "lib-002"])
        #expect(decoded.authors.count == 2)
        #expect(decoded.authors[1].lastName == "Толстой")
        #expect(decoded.books.count == 1)
        #expect(decoded.books[0].title == "Война и мир")
        #expect(decoded.books[0].libid == 100001)
    }

    @Test("magic header is FBLC; bad magic causes throw")
    func badMagic() throws {
        var bad = Data([0x00, 0x00, 0x00, 0x00])
        bad.append(Data(count: 100))
        #expect(throws: LibraryBinaryCodec.DecodeError.self) {
            try LibraryBinaryCodec.decode(bad)
        }
    }
}
