import Foundation

nonisolated struct Book: Identifiable, Hashable, Sendable {
    /// LIBID from INPX — the book's unique identifier inside the catalog.
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
    /// Дата добавления в библиотеку Флибусты — не на машину пользователя.
    /// Полночь того дня, что записан в INPX строкой `YYYY-MM-DD`.
    /// `nil` — даты в записи не было.
    let dateAdded: Date?
    let archiveFileName: String?

    init(libid: Int32, title: String, authorIDs: [Int32], seriesID: Int32?,
         seriesNum: Int16?, genreIDs: [Int16], language: String, archiveIndex: Int16,
         size: Int32, dateAdded: Date?, archiveFileName: String? = nil) {
        self.libid = libid
        self.title = title
        self.authorIDs = authorIDs
        self.seriesID = seriesID
        self.seriesNum = seriesNum
        self.genreIDs = genreIDs
        self.language = language
        self.archiveIndex = archiveIndex
        self.size = size
        self.dateAdded = dateAdded
        self.archiveFileName = archiveFileName
    }

    var archiveEntryName: String { (archiveFileName ?? String(libid)) + ".fb2" }
}
