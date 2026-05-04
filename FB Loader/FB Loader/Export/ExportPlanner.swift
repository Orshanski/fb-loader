import Foundation

nonisolated struct ExportItem {
    let book: Book
    let archiveURL: URL?       // nil if archivesRoot not provided yet (UI sets later)
    let destination: URL
}

nonisolated enum ExportPlanner {
    /// Forbidden in HFS+/APFS filenames or commonly problematic across tools.
    private static let forbidden: Set<Character> = [":", "/", "\\", "?", "*", "<", ">", "|", "\""]
    /// macOS filename limit (NAME_MAX) is 255; we cap a bit lower for safety.
    private static let nameMax = 220

    static func plan(libids: Set<Int32>,
                     rootFolder: URL,
                     selectedAuthorID: Int32?,
                     selectedSeriesID: Int32?,
                     in library: Library) -> [ExportItem] {
        // Use the precomputed indices on Library — building a fresh
        // 700k-entry Dictionary on every export was the original cost here.
        // selectedSeriesID is accepted by the public API for future use
        // (series-grouped export) but currently not part of folder-naming —
        // folders are always per-author. See "Как именуются файлы при
        // экспорте" in README.
        _ = selectedSeriesID
        return libids.compactMap { library.bookByLibid[$0] }.map { book in
            let folderName = folderName(for: book,
                                        selectedAuthorID: selectedAuthorID,
                                        authorsByID: library.authorByID)
            let folder = rootFolder.appendingPathComponent(sanitized(folderName), isDirectory: true)
            let dest = folder.appendingPathComponent(sanitized(book.title) + ".fb2")
            return ExportItem(book: book, archiveURL: nil, destination: dest)
        }
    }

    private static func folderName(for book: Book,
                                   selectedAuthorID: Int32?,
                                   authorsByID: [Int32: Author]) -> String {
        // 1. If user has selected an author in the sidebar — use that author's name,
        //    even if they are not the first author of the book.
        if let aid = selectedAuthorID, let a = authorsByID[aid] {
            return a.displayName
        }
        // 2. Else use the first author of the book.
        if let firstID = book.authorIDs.first, let a = authorsByID[firstID] {
            return a.displayName
        }
        return Author.unknown.displayName
    }

    static func sanitized(_ name: String) -> String {
        var s = String(name.map { forbidden.contains($0) ? "_" : $0 })
        if s.utf8.count > nameMax {
            s = String(s.prefix(nameMax))
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
