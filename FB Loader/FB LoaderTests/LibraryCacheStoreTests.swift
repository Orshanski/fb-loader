import Testing
import Foundation
@testable import FB_Loader

@Suite("LibraryCacheStore")
final class LibraryCacheStoreTests {
    private let tmp: URL
    private let store: LibraryCacheStore
    private let inpx: URL
    private let dict: GenreDictionary
    private let key = Data(repeating: 0x11, count: 32)

    init() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        store = LibraryCacheStore(applicationSupportRoot: tmp)
        inpx = try #require(TestBundleAnchor.bundle.url(forResource: "tiny", withExtension: "inpx"))
        dict = try GenreDictionary.loadFromBundle()
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        try? FileManager.default.removeItem(at: tmp)
    }

    private var cachePath: URL { LibraryCacheStore.cacheURL(in: tmp) }

    /// Загрузка с отметкой, понадобилась ли пересборка.
    private func load(sourceKey: Data? = nil) throws -> (Library, rebuilt: Bool) {
        var rebuilt = false
        let lib = try store.loadOrRebuild(inpxURL: inpx, sourceKey: sourceKey ?? key) { hash in
            rebuilt = true
            return try INPXImporter.parse(inpxURL: inpx, inpxHash: hash, genres: dict)
        }
        return (lib, rebuilt)
    }

    @Test("invalidate удаляет кэш — следующая загрузка собирает из INPX")
    func invalidateForcesRebuild() throws {
        _ = try load()
        #expect(FileManager.default.fileExists(atPath: cachePath.path))

        try store.invalidate()

        #expect(!FileManager.default.fileExists(atPath: cachePath.path))
        #expect(try load().rebuilt)
    }

    @Test("invalidate без кэша — не ошибка")
    func invalidateWithoutCache() throws {
        try store.invalidate()
    }

    @Test("первый вызов собирает из INPX, второй читает кэш")
    func reparseThenLoad() throws {
        let first = try load()
        #expect(first.rebuilt)
        #expect(first.0.books.count == 2)
        let second = try load()
        #expect(!second.rebuilt)
        #expect(second.0.books.count == 2)
    }

    @Test("пересборке передаётся уже посчитанный хеш INPX")
    func rebuildGetsHash() throws {
        var received: Data?
        _ = try store.loadOrRebuild(inpxURL: inpx, sourceKey: key) { hash in
            received = hash
            return try INPXImporter.parse(inpxURL: inpx, inpxHash: hash, genres: dict)
        }
        #expect(received == (try SHA256.hash(ofFileAt: inpx)))
    }

    @Test("другой хеш INPX в кэше — пересборка")
    func hashMismatchInvalidates() throws {
        _ = try load()
        // Layout: 4 magic + 2 version + 32 hash. Flip a byte inside the hash region.
        var data = try Data(contentsOf: cachePath)
        data[6] ^= 0xFF
        try data.write(to: cachePath)
        #expect(try load().rebuilt)
    }

    @Test("другая версия импортёра или жанров — пересборка")
    func sourceKeyMismatchInvalidates() throws {
        _ = try load()
        #expect(try load(sourceKey: Data(repeating: 0x22, count: 32)).rebuilt)
    }

    @Test("битый кэш — пересборка, а не падение")
    func corruptCacheRebuilds() throws {
        _ = try load()
        var data = try Data(contentsOf: cachePath)
        data.replaceSubrange((data.count - 40)..<data.count, with: Data(repeating: 0xFF, count: 40))
        try data.write(to: cachePath)
        #expect(try load().rebuilt)
    }

    @Test("кэш не записался — каталог всё равно открывается")
    func saveFailureIsNotFatal() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tmp.path)
        let result = try load()
        #expect(result.rebuilt)
        #expect(result.0.books.count == 2)
    }

    @Test("ключ источника: 32 байта и стабилен")
    func sourceKey() throws {
        let k1 = LibraryCacheStore.sourceKey(genres: dict)
        let k2 = LibraryCacheStore.sourceKey(genres: try GenreDictionary.loadFromBundle())
        #expect(k1.count == 32)
        #expect(k1 == k2)
    }
}
