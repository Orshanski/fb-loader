import Foundation

/// Reads one FB2 from a Flibusta .zip via `ZipCentralDirectory`. The old ZIPFoundation path took ~20 s per book
/// on a 1.5 GB archive on external storage; now the CD is read once per archive and cached.
nonisolated final class ZipFB2Reader {
    enum ReaderError: Error {
        case archiveNotFound(URL)
        case archiveUnreadable(URL, underlying: Error)
        case archiveCorrupt(URL, underlying: Error)
        case bookNotFoundInArchive(zip: URL, entryName: String)
    }

    private struct FileStamp: Equatable {
        let size: UInt64
        let modified: Date
    }

    /// CD indices per archive URL; the `nonisolated(unsafe)` dict is guarded by `cacheLock`.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var indexCache: [URL: (stamp: FileStamp, index: ZipCentralDirectory.Index)] = [:]

    static func readFB2(entryName name: String, archiveURL: URL) throws -> Data {
        // Не `URL.resourceValues`: он кэширует значения и подмену не заметит.
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ReaderError.archiveNotFound(archiveURL)
        }
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        } catch {
            throw ReaderError.archiveUnreadable(archiveURL, underlying: error)
        }
        guard let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let modified = attrs[.modificationDate] as? Date else {
            throw ReaderError.archiveNotFound(archiveURL)
        }

        let index = try cachedIndex(for: archiveURL, stamp: FileStamp(size: size, modified: modified))
        guard let entry = index.entries[name] else {
            throw ReaderError.bookNotFoundInArchive(zip: archiveURL, entryName: name)
        }
        // Карточка книги бросает чтение при смене книги; экспорт идёт в
        // неотменяемой задаче, его это не задевает.
        try Task.checkCancellation()
        do {
            return try ZipCentralDirectory.extract(entry, from: archiveURL)
        } catch {
            throw ReaderError.archiveCorrupt(archiveURL, underlying: error)
        }
    }

    private static func cachedIndex(for archiveURL: URL, stamp: FileStamp) throws -> ZipCentralDirectory.Index {
        cacheLock.lock()
        if let hit = indexCache[archiveURL], hit.stamp == stamp {
            cacheLock.unlock()
            return hit.index
        }
        cacheLock.unlock()
        let index: ZipCentralDirectory.Index
        do {
            index = try ZipCentralDirectory.readIndex(of: archiveURL)
        } catch {
            throw ReaderError.archiveCorrupt(archiveURL, underlying: error)
        }
        cacheLock.lock()
        indexCache[archiveURL] = (stamp, index)
        cacheLock.unlock()
        return index
    }
}
