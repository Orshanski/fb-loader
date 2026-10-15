import Foundation

/// Caches the parsed Library on disk and decides whether to reparse.
/// Cache is invalidated when the SHA-256 of the INPX content changes
/// (path is not a factor — same INPX moved elsewhere does not invalidate)
/// or when the importer or genres.json change.
nonisolated final class LibraryCacheStore {
    static let fileName = "library-cache.bin"

    static func cacheURL(in applicationSupportRoot: URL) -> URL {
        applicationSupportRoot.appendingPathComponent(fileName)
    }

    static func sourceKey(genres: GenreDictionary) -> Data {
        var bytes = Data()
        withUnsafeBytes(of: INPXImporter.logicVersion.littleEndian) { bytes.append(contentsOf: $0) }
        bytes.append(genres.fingerprint)
        return SHA256.hash(of: bytes)
    }

    private let cacheURL: URL

    init(applicationSupportRoot: URL) {
        try? FileManager.default.createDirectory(
            at: applicationSupportRoot,
            withIntermediateDirectories: true)
        self.cacheURL = Self.cacheURL(in: applicationSupportRoot)
    }

    func loadOrRebuild(
        inpxURL: URL,
        sourceKey: Data,
        forceRebuild: Bool = false,
        onStatus: (@Sendable (String) -> Void)? = nil,
        rebuild: (_ inpxHash: Data) throws -> Library
    ) throws -> Library {
        let currentHash = try SHA256.hash(ofFileAt: inpxURL)
        try Task.checkCancellation()

        if !forceRebuild, cachedHeader() == .init(inpxHash: currentHash, sourceKey: sourceKey) {
            do {
                let cached = try LibraryBinaryCodec.decode(Data(contentsOf: cacheURL), onStatus: onStatus)
                try Task.checkCancellation()
                return cached
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                print("[LibraryCacheStore] cache unreadable (\(error)) — rebuilding")
            }
        }

        let fresh = try rebuild(currentHash)
        // Отменённая загрузка не пишет кэш: его прочитала бы следующая.
        try Task.checkCancellation()
        do {
            try save(fresh, sourceKey: sourceKey)
        } catch {
            print("[LibraryCacheStore] cache not saved: \(error)")
        }
        return fresh
    }

    private func cachedHeader() -> LibraryBinaryCodec.Header? {
        guard let handle = try? FileHandle(forReadingFrom: cacheURL) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: LibraryBinaryCodec.headerSize) else { return nil }
        return try? LibraryBinaryCodec.readHeader(head)
    }

    private func save(_ lib: Library, sourceKey: Data) throws {
        // `.atomic` writes to a temp file, then renames over the destination via
        // POSIX rename — already crash-safe. No need for a manual remove+move.
        let data = try LibraryBinaryCodec.encode(lib, sourceKey: sourceKey)
        try data.write(to: cacheURL, options: [.atomic])
    }
}
