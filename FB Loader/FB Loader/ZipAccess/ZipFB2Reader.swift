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

    /// In-memory cache of CD indices keyed by archive URL. Cheap (~few MB
    /// per archive); first touch builds the index, subsequent touches are
    /// instant. The lock is a `let` of a Sendable type so it sits in
    /// nonisolated storage cleanly. The dict is `nonisolated(unsafe) var`
    /// because it's mutable and we synchronise access through the lock.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var indexCache: [URL: ZipCentralDirectory.Index] = [:]

    static func readFB2(libid: Int32, archiveURL: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ReaderError.archiveNotFound(archiveURL)
        }

        let index = try cachedIndex(for: archiveURL)
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

    private static func cachedIndex(for archiveURL: URL) throws -> ZipCentralDirectory.Index {
        cacheLock.lock()
        if let hit = indexCache[archiveURL] {
            cacheLock.unlock()
            return hit
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
        indexCache[archiveURL] = index
        cacheLock.unlock()
        return index
    }
}
