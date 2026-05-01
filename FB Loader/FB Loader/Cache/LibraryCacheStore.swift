import Foundation

/// Caches the parsed Library on disk and decides whether to reparse.
/// Cache is invalidated when the SHA-256 of the INPX content changes
/// (path is not a factor — same INPX moved elsewhere does not invalidate).
final class LibraryCacheStore {
    private let cacheURL: URL

    init(applicationSupportRoot: URL) {
        try? FileManager.default.createDirectory(
            at: applicationSupportRoot,
            withIntermediateDirectories: true)
        self.cacheURL = applicationSupportRoot.appendingPathComponent("library-cache.bin")
    }

    func loadOrRebuild(
        inpxURL: URL,
        genres: GenreDictionary,
        rebuild: () throws -> Library
    ) throws -> Library {
        let currentHash = try SHA256.hash(ofFileAt: inpxURL)

        if let cached = try? Data(contentsOf: cacheURL),
           let lib = try? LibraryBinaryCodec.decode(cached),
           lib.inpxHash == currentHash {
            return lib
        }

        let fresh = try rebuild()
        try save(fresh)
        return fresh
    }

    private func save(_ lib: Library) throws {
        let data = try LibraryBinaryCodec.encode(lib)
        let tmp = cacheURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: [.atomic])
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try FileManager.default.removeItem(at: cacheURL)
        }
        try FileManager.default.moveItem(at: tmp, to: cacheURL)
    }
}
