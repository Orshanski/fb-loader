import Foundation

struct ExportItem {
    let book: Book
    let archiveURL: URL?       // nil if archivesRoot not provided yet (UI sets later)
    let destination: URL
}

enum ExportPlanner {
    /// Forbidden in HFS+/APFS filenames or commonly problematic across tools.
    private static let forbidden: Set<Character> = [":", "/", "\\", "?", "*", "<", ">", "|", "\""]
    /// macOS filename limit (NAME_MAX) is 255; we cap a bit lower for safety.
    private static let nameMax = 220

    static func plan(libids: Set<Int32>,
                     rootFolder: URL,
                     selectedAuthorID: Int32?,
                     selectedSeriesID: Int32?,
                     in library: Library) -> [ExportItem] {
        let booksByLibid = Dictionary(uniqueKeysWithValues: library.books.map { ($0.libid, $0) })
        let authorsByID = Dictionary(uniqueKeysWithValues: library.authors.map { ($0.id, $0) })
        return libids.compactMap { id in booksByLibid[id] }.map { book in
            let folderName = folderName(for: book,
                                        selectedAuthorID: selectedAuthorID,
                                        selectedSeriesID: selectedSeriesID,
                                        authorsByID: authorsByID)
            let folder = rootFolder.appendingPathComponent(sanitized(folderName), isDirectory: true)
            let dest = folder.appendingPathComponent(sanitized(book.title) + ".fb2")
            return ExportItem(book: book, archiveURL: nil, destination: dest)
        }
    }

    private static func folderName(for book: Book,
                                   selectedAuthorID: Int32?,
                                   selectedSeriesID: Int32?,
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
