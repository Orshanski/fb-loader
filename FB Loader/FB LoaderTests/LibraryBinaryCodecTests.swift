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

    @Test("truncated data throws DecodeError.truncated")
    func truncated() throws {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: [], authors: [], series: [], genres: [], books: []
        )
        let full = try LibraryBinaryCodec.encode(lib)
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
        var data = try LibraryBinaryCodec.encode(lib)
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
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            ]
        )
        let decoded = try LibraryBinaryCodec.decode(LibraryBinaryCodec.encode(lib))
        #expect(decoded.books[0].seriesID == nil)
        #expect(decoded.books[0].seriesNum == nil)
    }

    @Test("non-32-byte inpxHash throws EncodeError.invalidHashSize")
    func invalidHashSize() throws {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 16),     // wrong size
            inpxVersion: "v",
            archives: [], authors: [], series: [], genres: [], books: []
        )
        #expect(throws: LibraryBinaryCodec.EncodeError.self) {
            try LibraryBinaryCodec.encode(lib)
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
                     language: "ru", archiveIndex: 1, size: 0, dateAddedDays: 0),
            ]
        )
        let data = try LibraryBinaryCodec.encode(lib)

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
        let data = try LibraryBinaryCodec.encode(original)

        // Collect status messages fired during decode → Library.init.
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

/// Test helper — thread-safe box for collecting messages fired from
/// non-MainActor contexts. `Library.init`'s `onStatus` is `@Sendable`, so
/// the closure can be called from any actor; we need a safe place to
/// accumulate.
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
