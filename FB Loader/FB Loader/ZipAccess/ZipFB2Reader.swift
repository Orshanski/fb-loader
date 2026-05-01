import Foundation
import ZIPFoundation

/// Opens a zip archive and extracts a single FB2 file into memory.
/// Uses ZIPFoundation, which performs random access via the central directory.
///
/// `nonisolated` — under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` this would
/// otherwise be inferred as MainActor and refuse to be called from `Task.detached`
/// (e.g. from `ExportRunner`). It's a pure file-I/O utility, no UI state.
final class ZipFB2Reader {
    enum ReaderError: Error {
        case archiveNotFound(URL)
        /// Wraps the actual ZIPFoundation error so the cause is visible in logs.
        case archiveCorrupt(URL, underlying: Error)
        case bookNotFoundInArchive(zip: URL, libid: Int32)
    }

    /// Reads the bytes of `<libid>.fb2` from the given zip.
    nonisolated static func readFB2(libid: Int32, archiveURL: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ReaderError.archiveNotFound(archiveURL)
        }
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw ReaderError.archiveCorrupt(archiveURL, underlying: error)
        }
        let name = "\(libid).fb2"
        guard let entry = archive[name] else {
            throw ReaderError.bookNotFoundInArchive(zip: archiveURL, libid: libid)
        }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }
}
