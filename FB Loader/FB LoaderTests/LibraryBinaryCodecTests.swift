import Testing
import Foundation
@testable import FB_Loader

private let testKey = Data(repeating: 0xCD, count: 32)

private func book(_ libid: Int32, authors: [Int32] = [Author.unknownID], series: Int32? = nil,
                  genres: [Int16] = [], archiveFileName: String? = nil) -> Book {
    Book(libid: libid, title: "t", authorIDs: authors, seriesID: series, seriesNum: nil,
         genreIDs: genres, language: "ru", archiveIndex: 0, size: 0, dateAdded: nil,
         archiveFileName: archiveFileName)
}

private func library(authors: [Author] = [Author.unknown], series: [Series] = [],
                     genres: [Genre] = [], books: [Book]) -> Library {
    Library(inpxHash: Data(repeating: 0xAB, count: 32), inpxVersion: "v", archives: ["arch"],
            authors: authors, series: series, genres: genres, books: books)
}

@Suite("LibraryBinaryCodec — целостность")
struct LibraryBinaryCodecIntegrityTests {
    @Test("разбор среза Data с ненулевым startIndex")
    func dataSlice() throws {
        let full = try LibraryBinaryCodec.encode(library(books: [book(1, archiveFileName: "f")]),
                                                 sourceKey: testKey)
        let slice = (Data([0xAA]) + full).dropFirst()
        #expect(slice.startIndex == 1)
        #expect(try LibraryBinaryCodec.readHeader(slice).sourceKey == testKey)
        #expect(try LibraryBinaryCodec.decode(slice).books.map(\.archiveEntryName) == ["f.fb2"])
    }

    @Test("заголовок читается без разбора каталога")
    func header() throws {
        let data = try LibraryBinaryCodec.encode(library(books: [book(1)]), sourceKey: testKey)
        let h = try LibraryBinaryCodec.readHeader(data.prefix(LibraryBinaryCodec.headerSize))
        #expect(h.inpxHash == Data(repeating: 0xAB, count: 32))
        #expect(h.sourceKey == testKey)
    }

    @Test("имя файла в архиве и синтетический жанр переживают кэш")
    func archiveFileNameAndSyntheticGenre() throws {
        let lib = library(genres: [Genre(id: -1, code: "x_new", name: "x_new", parentID: nil)],
                          books: [book(1, genres: [-1], archiveFileName: "book-1"), book(2)])
        let decoded = try LibraryBinaryCodec.decode(LibraryBinaryCodec.encode(lib, sourceKey: testKey))
        #expect(decoded.books.map(\.archiveEntryName) == ["book-1.fb2", "2.fb2"])
        #expect(decoded.genreByID[-1]?.code == "x_new")
    }

    @Test("слишком много авторов у книги — ошибка записи, а не падение")
    func tooManyAuthors() {
        let ids = (0..<70_000).map { _ in Author.unknownID }
        #expect(throws: LibraryBinaryCodec.EncodeError.self) {
            try LibraryBinaryCodec.encode(library(books: [book(1, authors: ids)]), sourceKey: testKey)
        }
    }

    @Test("ссылка на несуществующего автора — ошибка чтения, а не падение позже")
    func danglingAuthor() throws {
        let data = try LibraryBinaryCodec.encode(library(books: [book(1, authors: [42])]), sourceKey: testKey)
        #expect(throws: LibraryBinaryCodec.DecodeError.self) {
            try LibraryBinaryCodec.decode(data)
        }
    }

    @Test("ссылки на несуществующие серию и жанр — ошибка чтения")
    func danglingSeriesAndGenre() throws {
        for b in [book(1, series: 7), book(1, genres: [9])] {
            let data = try LibraryBinaryCodec.encode(library(books: [b]), sourceKey: testKey)
            #expect(throws: LibraryBinaryCodec.DecodeError.self) {
                try LibraryBinaryCodec.decode(data)
            }
        }
    }

    @Test("повтор id — ошибка проверки, а не падение в Library.init")
    func duplicateIDs() {
        let a = Author(id: 5, lastName: "А", firstName: "", middleName: "")
        #expect(throws: LibraryBinaryCodec.DecodeError.self) {
            try LibraryBinaryCodec.validate(authors: [a, a], series: [], genres: [], books: [])
        }
        let s = Series(id: 3, name: "С")
        #expect(throws: LibraryBinaryCodec.DecodeError.self) {
            try LibraryBinaryCodec.validate(authors: [], series: [s, s], genres: [], books: [])
        }
        let g = Genre(id: 2, code: "g", name: "g", parentID: nil)
        #expect(throws: LibraryBinaryCodec.DecodeError.self) {
            try LibraryBinaryCodec.validate(authors: [], series: [], genres: [g, g], books: [])
        }
    }
}

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
                     language: "ru", archiveIndex: 0, size: 987654, dateAdded: Date(timeIntervalSinceReferenceDate: 400_000_000)),
            ]
        )
        let data = try LibraryBinaryCodec.encode(original, sourceKey: testKey)
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

    @Test("truncated data throws DecodeError.truncated")
    func truncated() throws {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: [], authors: [], series: [], genres: [], books: []
        )
        let full = try LibraryBinaryCodec.encode(lib, sourceKey: testKey)
        // Cut at byte 10 — past magic and version, mid-hash.
        let truncated = full.prefix(10)
        #expect(throws: LibraryBinaryCodec.DecodeError.self) {
            try LibraryBinaryCodec.decode(truncated)
        }
    }

    @Test("unsupported format version throws")
    func unsupportedVersion() throws {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: [], authors: [], series: [], genres: [], books: []
        )
        var data = try LibraryBinaryCodec.encode(lib, sourceKey: testKey)
        // Bytes 4..5 are the format-version little-endian UInt16; flip to 99.
        data[4] = 99
        data[5] = 0
        #expect(throws: LibraryBinaryCodec.DecodeError.self) {
            try LibraryBinaryCodec.decode(data)
        }
    }

    @Test("nil seriesID and seriesNum survive round-trip via sentinel encoding")
    func nilOptionalsRoundTrip() throws {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [Author.unknown],
            series: [],
            genres: [],
            books: [
                Book(libid: 1, title: "t", authorIDs: [Author.unknownID],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
            ]
        )
        let decoded = try LibraryBinaryCodec.decode(LibraryBinaryCodec.encode(lib, sourceKey: testKey))
        #expect(decoded.books[0].seriesID == nil)
        #expect(decoded.books[0].seriesNum == nil)
    }

    @Test("non-32-byte inpxHash throws EncodeError.invalidHashSize")
    func invalidHashSize() throws {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 16),
            inpxVersion: "v",
            archives: [], authors: [], series: [], genres: [], books: []
        )
        #expect(throws: LibraryBinaryCodec.EncodeError.self) {
            try LibraryBinaryCodec.encode(lib, sourceKey: testKey)
        }
    }

    @Test("decode rejects book archive indexes outside archives array")
    func invalidArchiveIndex() throws {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [Author.unknown],
            series: [],
            genres: [],
            books: [
                Book(libid: 1, title: "t", authorIDs: [Author.unknownID],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 1, size: 0, dateAdded: nil),
            ]
        )
        let data = try LibraryBinaryCodec.encode(lib, sourceKey: testKey)

        #expect(throws: LibraryBinaryCodec.DecodeError.self) {
            try LibraryBinaryCodec.decode(data)
        }
    }

    @Test("decode forwards onStatus to Library.init (cache-hit path shows search-index progress)")
    func decodeForwardsOnStatus() throws {
        let original = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [Author.unknown],
            series: [],
            genres: [],
            books: []
        )
        let data = try LibraryBinaryCodec.encode(original, sourceKey: testKey)

        let statuses = ThreadSafeBox<[String]>([])
        _ = try LibraryBinaryCodec.decode(data, onStatus: { msg in
            statuses.mutate { $0.append(msg) }
        })

        let collected = statuses.value
        // Library.init fires multiple status messages; we only assert that
        // the search-index status is among them — that's the regression
        // we're guarding against.
        #expect(collected.contains(where: { $0.contains("Считаем индексы поиска") }),
                "decode must forward onStatus to Library.init; collected=\(collected)")
    }
}

/// `Library.init`'s `onStatus` is `@Sendable` and may fire from any actor.
final class ThreadSafeBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value
    init(_ value: Value) { self.storage = value }
    var value: Value {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func mutate(_ block: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }
        block(&storage)
    }
}
