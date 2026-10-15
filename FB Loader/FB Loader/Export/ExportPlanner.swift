import Foundation

nonisolated struct ExportItem {
    let book: Book
    let archiveURL: URL?       // nil if archivesRoot not provided yet (UI sets later)
    let destination: URL
}

nonisolated enum ExportPlanner {
    /// Forbidden in HFS+/APFS filenames or commonly problematic across tools.
    private static let forbidden: Set<Character> = [":", "/", "\\", "?", "*", "<", ">", "|", "\""]
    /// APFS NAME_MAX — 255 байт UTF-8; запас под « (NN)» и «.fb2».
    static let nameByteLimit = 240
    private static let fileExtension = ".fb2"

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
        let books = libids.compactMap { library.book(libid: $0) }
            .sorted { ($0.archiveIndex, $0.libid) < ($1.archiveIndex, $1.libid) }
        var used: Set<String> = []
        return books.map { book in
            let folderName = folderName(for: book,
                                        selectedAuthorID: selectedAuthorID,
                                        library: library)
            let folder = rootFolder.appendingPathComponent(
                sanitized(folderName, fallback: Author.unknown.displayName), isDirectory: true)
            let title = sanitized(book.title)
            var dest = folder.appendingPathComponent(title + fileExtension)
            var n = 2
            // APFS по умолчанию не различает регистр и форму нормализации.
            while !used.insert(dest.path.decomposedStringWithCanonicalMapping.lowercased()).inserted {
                let suffix = " (\(n))"
                let base = truncated(title, toBytes: nameByteLimit - byteCount(suffix))
                dest = folder.appendingPathComponent(base + suffix + fileExtension)
                n += 1
            }
            return ExportItem(book: book, archiveURL: nil, destination: dest)
        }
    }

    private static func folderName(for book: Book,
                                   selectedAuthorID: Int32?,
                                   library: Library) -> String {
        // 1. If user has selected an author in the sidebar — use that author's name,
        //    even if they are not the first author of the book.
        if let aid = selectedAuthorID, let a = library.author(id: aid) {
            return a.displayName
        }
        // 2. Else use the first author of the book.
        if let firstID = book.authorIDs.first, let a = library.author(id: firstID) {
            return a.displayName
        }
        return Author.unknown.displayName
    }

    static func sanitized(_ name: String, fallback: String = "_") -> String {
        let replaced = String(name.map { ch in
            forbidden.contains(ch) || ch.unicodeScalars.contains { $0.properties.generalCategory == .control }
                ? "_" : ch
        })
        var s = Substring(replaced.trimmingCharacters(in: .whitespacesAndNewlines))
        let dots = s.prefix { $0 == "." }.count
        s = String(repeating: "_", count: dots) + s.dropFirst(dots)
        let result = truncated(String(s), toBytes: nameByteLimit)
        return result.isEmpty ? fallback : result
    }

    /// Foundation отдаёт имя в файловую систему в NFD: «й» там занимает 4 байта, а не 2.
    private static func byteCount(_ s: String) -> Int {
        s.decomposedStringWithCanonicalMapping.utf8.count
    }

    private static func truncated(_ s: String, toBytes limit: Int) -> String {
        guard byteCount(s) > limit else { return s }
        var bytes = 0
        let kept = s.prefix { ch in
            bytes += byteCount(String(ch))
            return bytes <= limit
        }
        return String(kept).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
