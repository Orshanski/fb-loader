import Foundation

nonisolated struct Book: Identifiable, Hashable, Sendable {
    /// LIBID from INPX — the book's unique identifier inside the catalog.
    /// Also the filename inside the zip archive: "<libid>.fb2".
    let libid: Int32
    var id: Int32 { libid }

    let title: String
    let authorIDs: [Int32]      // first is primary
    let seriesID: Int32?
    let seriesNum: Int16?
    let genreIDs: [Int16]
    let language: String        // "ru", "en", or "" for unknown
    /// Index into `Library.archives` array (the zip filename without .zip extension).
    let archiveIndex: Int16
    /// Size in bytes (from INPX).
    let size: Int32
    /// Date added to the Flibusta library, not to the user's machine.
    /// Encoded as days since 2000-01-01 (4 bytes vs 8 of Date).
    let dateAddedDays: Int32
}

nonisolated extension Book {
    static let dateEpoch: Date = {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    var dateAdded: Date {
        // Force-unwrap is safe: INPXImporter (Phase 3) sources dateAddedDays from
        // a parsed YYYY-MM-DD field that always falls within Calendar's representable range.
        // The Calendar's timezone does not affect whole-day arithmetic on `dateEpoch` (UTC).
        Calendar(identifier: .gregorian).date(byAdding: .day, value: Int(dateAddedDays), to: Book.dateEpoch)!
    }
}
