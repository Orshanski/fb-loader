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
        let store = LibraryCacheStore(applicationSupportRoot: tmp)
        let inpx = try #require(Bundle(for: TinyAnchor2.self)
            .url(forResource: "tiny", withExtension: "inpx"))
        let dict = try GenreDictionary.loadFromBundle()

        var didReparse = false
        let lib1 = try store.loadOrRebuild(inpxURL: inpx, genres: dict) {
            didReparse = true
            return try INPXImporter.import_(inpxURL: inpx, genres: dict)
        }
        #expect(didReparse == true)
        #expect(lib1.books.count == 2)

        // Second call: hash matches → use cache.
        var didReparseAgain = false
        let lib2 = try store.loadOrRebuild(inpxURL: inpx, genres: dict) {
            didReparseAgain = true
            return try INPXImporter.import_(inpxURL: inpx, genres: dict)
        }
        #expect(didReparseAgain == false)
        #expect(lib2.books.count == 2)
    }
}
private final class TinyAnchor2 {}
