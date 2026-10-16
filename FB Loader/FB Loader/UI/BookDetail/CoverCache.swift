import Foundation
import AppKit

/// Disk-backed jpg cache for FB2 cover images at
/// `~/Library/Caches/<bundleID>/covers/<libid>.jpg`. Caller extracts cover
/// bytes from an already-parsed `FB2BookInfo` and calls `store(_:for:)`;
/// next visit hits `cachedImage(for:)` directly.
///
/// `nonisolated final class`: only state is the immutable `cacheDir` URL,
/// disk writes go through `Data.write(options: .atomic)`, and concurrent
/// reads of a cached file are safe at the OS level.
nonisolated final class CoverCache: Sendable {
    static let defaultLimitBytes = 200 * 1024 * 1024

    static let shared: CoverCache? = {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .cachesDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "FB-Loader",
                                              isDirectory: true)
            .appendingPathComponent("covers", isDirectory: true)
        return try? CoverCache(directory: dir)
    }()

    private let cacheDir: URL
    private let limitBytes: Int

    init(directory: URL, limitBytes: Int = CoverCache.defaultLimitBytes) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.cacheDir = directory
        self.limitBytes = limitBytes
    }

    /// Disk-cached cover, if previously stored. Caller checks this first; on
    /// miss, the caller is responsible for extracting cover bytes from an
    /// already-parsed `FB2BookInfo` and calling `store(_:for:)` to persist.
    func cachedImage(for book: Book) -> NSImage? {
        let url = cacheURL(for: book)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        // Обновляем дату изменения при попадании: вытеснение по ней становится LRU (atime на APFS ненадёжен).
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return NSImage(contentsOf: url)
    }

    /// Writes cover bytes to the disk cache and returns an NSImage for them.
    func store(_ coverBytes: Data, for book: Book) -> NSImage? {
        let url = cacheURL(for: book)
        try? coverBytes.write(to: url, options: .atomic)
        trimToLimit(keeping: url)
        return NSImage(data: coverBytes)
    }

    /// Удаляет самые давно использованные файлы, пока размер не опустится до 90% лимита:
    /// запас избавляет от обхода каталога на каждой следующей записи. Вызывать вне main actor.
    func trimToLimit(keeping keep: URL? = nil) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: keys) else { return }
        var files: [(url: URL, size: Int, date: Date)] = urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), let size = v.fileSize else { return nil }
            return (u, size, v.contentModificationDate ?? .distantPast)
        }
        var total = files.reduce(0) { $0 + $1.size }
        guard total > limitBytes else { return }
        let target = limitBytes / 10 * 9
        files.sort { $0.date < $1.date }
        for f in files where total > target {
            if f.url.standardizedFileURL == keep?.standardizedFileURL { continue }
            if (try? fm.removeItem(at: f.url)) != nil { total -= f.size }
        }
    }

    private func cacheURL(for book: Book) -> URL {
        cacheDir.appendingPathComponent("\(book.libid).jpg")
    }
}
