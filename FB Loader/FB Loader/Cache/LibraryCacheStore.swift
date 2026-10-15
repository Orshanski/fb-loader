import Foundation

/// Caches the parsed Library on disk and decides whether to reparse.
/// Cache is invalidated when the SHA-256 of the INPX content changes
/// (path is not a factor — same INPX moved elsewhere does not invalidate)
/// or when the source key changes: новая версия импортёра или genres.json
/// в обновлении приложения собирают из того же INPX другой каталог.
nonisolated final class LibraryCacheStore {
    static let fileName = "library-cache.bin"

    static func cacheURL(in applicationSupportRoot: URL) -> URL {
        applicationSupportRoot.appendingPathComponent(fileName)
    }

    /// Ключ всего, кроме INPX, от чего зависит собранный каталог.
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

    /// `rebuild` получает уже посчитанный хеш INPX.
    func loadOrRebuild(
        inpxURL: URL,
        sourceKey: Data,
        onStatus: (@Sendable (String) -> Void)? = nil,
        rebuild: (_ inpxHash: Data) throws -> Library
    ) throws -> Library {
        let currentHash = try SHA256.hash(ofFileAt: inpxURL)

        // Заголовок сверяется до полного разбора: устаревший кэш не тратит
        // секунды на декод и построение индексов, которые тут же выбросятся.
        if let cached = try? Data(contentsOf: cacheURL) {
            do {
                let header = try LibraryBinaryCodec.readHeader(cached)
                if header == .init(inpxHash: currentHash, sourceKey: sourceKey) {
                    return try LibraryBinaryCodec.decode(cached, onStatus: onStatus)
                }
                print("[LibraryCacheStore] cache is stale — rebuilding")
            } catch {
                print("[LibraryCacheStore] cache unreadable (\(error)) — rebuilding")
            }
        }

        let fresh = try rebuild(currentHash)
        // Каталог собран — он нужен пользователю и без кэша. Ошибка записи
        // (диск полон, нет доступа) стоит только скорости следующего запуска.
        do {
            try save(fresh, sourceKey: sourceKey)
        } catch {
            print("[LibraryCacheStore] cache not saved: \(error)")
        }
        return fresh
    }

    func invalidate() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func save(_ lib: Library, sourceKey: Data) throws {
        // `.atomic` writes to a temp file, then renames over the destination via
        // POSIX rename — already crash-safe. No need for a manual remove+move.
        let data = try LibraryBinaryCodec.encode(lib, sourceKey: sourceKey)
        try data.write(to: cacheURL, options: [.atomic])
    }
}
