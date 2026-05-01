import Foundation
import AppKit

/// Lazy-fills `~/Library/Caches/<bundleID>/covers/<libid>.jpg`.
/// On a miss, opens the book's zip via ZipFB2Reader, parses the FB2 prefix,
/// extracts cover bytes, writes to disk.
///
/// `@unchecked Sendable` is sound here: the only state is the immutable
/// `cacheDir` URL; concurrent writes to disk go through atomic FileManager
/// operations (`Data.write(options: .atomic)`), and concurrent reads of an
/// already-cached file are safe at the OS level.
///
/// `image(for:in:archivesRoot:)` is `nonisolated` so it can be called from
/// `Task.detached` in `BookDetailView.loadDetail` (project default isolation
/// is MainActor). Constructor stays default-isolated; instances are created
/// on MainActor and shipped over the Sendable boundary into detached tasks.
final class CoverCache: @unchecked Sendable {
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
    nonisolated func cachedImage(for book: Book) -> NSImage? {
        let url = cacheURL(for: book)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Writes cover bytes to the disk cache and returns an NSImage for them.
    nonisolated func store(_ coverBytes: Data, for book: Book) -> NSImage? {
        let url = cacheURL(for: book)
        try? coverBytes.write(to: url, options: .atomic)
        return NSImage(data: coverBytes)
    }

    private nonisolated func cacheURL(for book: Book) -> URL {
        cacheDir.appendingPathComponent("\(book.libid).jpg")
    }
}
