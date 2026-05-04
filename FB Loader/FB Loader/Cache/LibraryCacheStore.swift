import Foundation

/// Caches the parsed Library on disk and decides whether to reparse.
/// Cache is invalidated when the SHA-256 of the INPX content changes
/// (path is not a factor — same INPX moved elsewhere does not invalidate).
nonisolated final class LibraryCacheStore {
    private let cacheURL: URL

    init(applicationSupportRoot: URL) {
        try? FileManager.default.createDirectory(
            at: applicationSupportRoot,
            withIntermediateDirectories: true)
        self.cacheURL = applicationSupportRoot.appendingPathComponent("library-cache.bin")
    }

    func loadOrRebuild(
        inpxURL: URL,
        onStatus: (@Sendable (String) -> Void)? = nil,
        rebuild: () throws -> Library
    ) throws -> Library {
        let currentHash = try SHA256.hash(ofFileAt: inpxURL)

        if let cached = try? Data(contentsOf: cacheURL),
           let lib = try? LibraryBinaryCodec.decode(cached, onStatus: onStatus),
           lib.inpxHash == currentHash {
            return lib
        }

        let fresh = try rebuild()
        try save(fresh)
        return fresh
    }

    private func save(_ lib: Library) throws {
        // `.atomic` writes to a temp file, then renames over the destination via
        // POSIX rename — already crash-safe. No need for a manual remove+move.
        let data = try LibraryBinaryCodec.encode(lib)
        try data.write(to: cacheURL, options: [.atomic])
    }
}
