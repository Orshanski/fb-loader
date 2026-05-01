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

    func image(for book: Book, in library: Library, archivesRoot: URL) -> NSImage? {
        let cached = cacheDir.appendingPathComponent("\(book.libid).jpg")
        if let img = NSImage(contentsOf: cached) { return img }
        // Parse FB2 to extract cover
        let archiveName = library.archives[Int(book.archiveIndex)] + ".zip"
        let archiveURL = archivesRoot.appendingPathComponent(archiveName)
        guard let fb2 = try? ZipFB2Reader.readFB2(libid: book.libid, archiveURL: archiveURL),
              let info = try? FB2DescriptionParser.parse(data: fb2.prefix(64 * 1024)),
              let cover = info.coverImageData else {
            return nil
        }
        try? cover.write(to: cached, options: .atomic)
        return NSImage(data: cover)
    }
}
