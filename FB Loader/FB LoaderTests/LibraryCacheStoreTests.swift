import Testing
import Foundation
@testable import FB_Loader

@Suite("LibraryCacheStore")
struct LibraryCacheStoreTests {
    @Test("first call reparses INPX; subsequent loads from cache")
    func reparseThenLoad() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = LibraryCacheStore(applicationSupportRoot: tmp)
        let inpx = try #require(Bundle(for: TinyAnchor2.self)
            .url(forResource: "tiny", withExtension: "inpx"))
        let dict = try GenreDictionary.loadFromBundle()

        var didReparse = false
        let lib1 = try store.loadOrRebuild(inpxURL: inpx) {
            didReparse = true
            return try INPXImporter.import_(inpxURL: inpx, genres: dict)
        }
        #expect(didReparse == true)
        #expect(lib1.books.count == 2)

        // Second call: hash matches → use cache.
        var didReparseAgain = false
        let lib2 = try store.loadOrRebuild(inpxURL: inpx) {
            didReparseAgain = true
            return try INPXImporter.import_(inpxURL: inpx, genres: dict)
        }
        #expect(didReparseAgain == false)
        #expect(lib2.books.count == 2)
    }

    @Test("hash mismatch invalidates the cache and forces a reparse")
    func hashMismatchInvalidates() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = LibraryCacheStore(applicationSupportRoot: tmp)
        let inpx = try #require(Bundle(for: TinyAnchor2.self)
            .url(forResource: "tiny", withExtension: "inpx"))
        let dict = try GenreDictionary.loadFromBundle()

        // Prime the cache.
        _ = try store.loadOrRebuild(inpxURL: inpx) {
            try INPXImporter.import_(inpxURL: inpx, genres: dict)
        }

        // Corrupt the stored inpxHash so it no longer matches the file's actual hash.
        // Layout: 4 magic + 2 version + 32 hash. Flip a byte inside the hash region.
        let cachePath = tmp.appendingPathComponent("library-cache.bin")
        var data = try Data(contentsOf: cachePath)
        data[6] ^= 0xFF
        try data.write(to: cachePath)

        var didReparse = false
        _ = try store.loadOrRebuild(inpxURL: inpx) {
            didReparse = true
            return try INPXImporter.import_(inpxURL: inpx, genres: dict)
        }
        #expect(didReparse == true)
    }
}
private final class TinyAnchor2 {}
