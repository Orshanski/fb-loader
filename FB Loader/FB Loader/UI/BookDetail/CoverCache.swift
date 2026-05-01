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
    private let cacheDir: URL

    init() throws {
        let fm = FileManager.default
        let base = try fm.url(for: .cachesDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "FB-Loader",
                                              isDirectory: true)
            .appendingPathComponent("covers", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDir = dir
    }

    /// Disk-cached cover, if previously stored. Caller checks this first; on
    /// miss, the caller is responsible for extracting cover bytes from an
    /// already-parsed `FB2BookInfo` and calling `store(_:for:)` to persist.
    func cachedImage(for book: Book) -> NSImage? {
        let url = cacheURL(for: book)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Writes cover bytes to the disk cache and returns an NSImage for them.
    func store(_ coverBytes: Data, for book: Book) -> NSImage? {
        let url = cacheURL(for: book)
        try? coverBytes.write(to: url, options: .atomic)
        return NSImage(data: coverBytes)
    }

    private func cacheURL(for book: Book) -> URL {
        cacheDir.appendingPathComponent("\(book.libid).jpg")
    }
}
