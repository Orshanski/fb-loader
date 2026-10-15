import Foundation

/// Reads a single FB2 file from a Flibusta-style .zip archive.
/// Uses our own ZIP central-directory reader (`ZipCentralDirectory`) — the
/// previous ZIPFoundation-based path took ~20 s per book on a 1.5 GB zip on
/// external storage because its iterator hits disk per CD record. The CD is
/// read once per archive in one big chunk, cached in memory, then any book
/// in that archive is fetched in <100 ms.
nonisolated final class ZipFB2Reader {
    enum ReaderError: Error {
        case archiveNotFound(URL)
        case archiveCorrupt(URL, underlying: Error)
        case bookNotFoundInArchive(zip: URL, libid: Int32)
    }

    /// Версия файла архива на диске. Индекс хранит смещения записей, поэтому
    /// архив, подменённый по тому же пути, должен переиндексироваться.
    private struct FileStamp: Equatable {
        let size: UInt64
        let modified: Date
    }

    /// In-memory cache of CD indices keyed by archive URL. Cheap (~few MB
    /// per archive); first touch builds the index, subsequent touches are
    /// instant. The lock is a `let` of a Sendable type so it sits in
    /// nonisolated storage cleanly. The dict is `nonisolated(unsafe) var`
    /// because it's mutable and we synchronise access through the lock.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var indexCache: [URL: (stamp: FileStamp, index: ZipCentralDirectory.Index)] = [:]

    static func readFB2(libid: Int32, archiveURL: URL) throws -> Data {
        // Атрибуты — через FileManager, а не `URL.resourceValues`: тот
        // кэширует значения на экземпляре URL и подмену бы не заметил.
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: archiveURL.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let modified = attrs[.modificationDate] as? Date else {
            throw ReaderError.archiveNotFound(archiveURL)
        }

        let index = try cachedIndex(for: archiveURL, stamp: FileStamp(size: size, modified: modified))
        let name = "\(libid).fb2"
        guard let entry = index.entries[name] else {
            throw ReaderError.bookNotFoundInArchive(zip: archiveURL, libid: libid)
        }
        do {
            let tExtract = ContinuousClock.now
            let data = try ZipCentralDirectory.extract(entry, from: archiveURL)
            print("[ZipFB2Reader] extract \(name): \(ContinuousClock.now - tExtract)")
            return data
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
        let tBuild = ContinuousClock.now
        let index: ZipCentralDirectory.Index
        do {
            index = try ZipCentralDirectory.readIndex(of: archiveURL)
        } catch {
            throw ReaderError.archiveCorrupt(archiveURL, underlying: error)
        }
        print("[ZipFB2Reader] index built for \(archiveURL.lastPathComponent) (\(index.entries.count) entries) in \(ContinuousClock.now - tBuild)")
        cacheLock.lock()
        indexCache[archiveURL] = (stamp, index)
        cacheLock.unlock()
        return index
    }
}
