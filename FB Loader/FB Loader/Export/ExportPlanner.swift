import Foundation

nonisolated struct ExportItem {
    let book: Book
    let archiveURL: URL
    let destination: URL
}

nonisolated enum ExportPlanner {
    /// Forbidden in HFS+/APFS filenames or commonly problematic across tools.
    private static let forbidden: Set<Character> = [":", "/", "\\", "?", "*", "<", ">", "|", "\""]
    /// Лимит имени папки; для файла — `limit(_:)`.
    static let nameByteLimit = 240

    /// 11 — запас под « (NN…)»; остальное — точка и расширение.
    static func limit(_ fileExtension: String) -> Int {
        255 - 11 - (1 + fileExtension.utf8.count)
    }

    static func plan(libids: Set<Int32>,
                     rootFolder: URL,
                     archivesRoot: URL,
                     selectedAuthorID: Int32?,
                     selectedSeriesID: Int32?,
                     format: ExportFormat = .fb2,
                     in library: Library) -> [ExportItem] {
        // selectedSeriesID is reserved for series-grouped export; folders are always per-author.
        _ = selectedSeriesID
        let books = libids.compactMap { library.book(libid: $0) }
            .sorted { ($0.archiveIndex, $0.libid) < ($1.archiveIndex, $1.libid) }
        let ext = "." + format.fileExtension
        let titleLimit = limit(format.fileExtension)
        var used: Set<String> = []
        return books.map { book in
            let folderName = folderName(for: book,
                                        selectedAuthorID: selectedAuthorID,
                                        library: library)
            let folder = rootFolder.appendingPathComponent(
                sanitized(folderName, fallback: Author.unknown.displayName), isDirectory: true)
            let title = sanitized(book.title, limit: titleLimit)
            var dest = folder.appendingPathComponent(title + ext)
            var n = 2
            // APFS по умолчанию не различает регистр и форму нормализации.
            while !used.insert(dest.path.decomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive], locale: nil)).inserted {
                let suffix = " (\(n))"
                let base = truncated(title, toBytes: titleLimit - byteCount(suffix))
                dest = folder.appendingPathComponent(base + suffix + ext)
                n += 1
            }
            return ExportItem(book: book,
                              archiveURL: archivesRoot.appendingPathComponent(library.archives[Int(book.archiveIndex)] + ".zip"),
                              destination: dest)
        }
    }

    private static func folderName(for book: Book,
                                   selectedAuthorID: Int32?,
                                   library: Library) -> String {
        // The author selected in the sidebar wins, even if they are not the book's first author.
        if let aid = selectedAuthorID, let a = library.author(id: aid) {
            return a.displayName
        }
        if let firstID = book.authorIDs.first, let a = library.author(id: firstID) {
            return a.displayName
        }
        return Author.unknown.displayName
    }

    /// Невидимые и управляющие символы в имени файла — путаница в Finder (U+202E разворачивает текст).
    private static let replacedCategories: Set<Unicode.GeneralCategory> =
        [.control, .format, .lineSeparator, .paragraphSeparator]

    static func sanitized(_ name: String, fallback: String = "_", limit: Int = nameByteLimit) -> String {
        let replaced = String(name.map { ch in
            forbidden.contains(ch)
                || ch.unicodeScalars.contains { replacedCategories.contains($0.properties.generalCategory) }
                ? "_" : ch
        })
        var s = Substring(replaced.trimmingCharacters(in: .whitespacesAndNewlines))
        let dots = s.prefix { $0 == "." }.count
        s = String(repeating: "_", count: dots) + s.dropFirst(dots)
        let result = truncated(String(s), toBytes: limit)
        return result.isEmpty ? fallback : result
    }

    private static func byteCount(_ s: String) -> Int {
        s.reduce(0) { $0 + byteCount($1) }
    }

    /// Foundation отдаёт имя в HFS+-декомпозиции ≈ NFD («й» — 4 байта), но синглтоны
    /// вроде U+212A она не раскладывает, поэтому берём максимум из форм.
    private static func byteCount(_ ch: Character) -> Int {
        let s = String(ch)
        return max(s.utf8.count,
                   s.precomposedStringWithCanonicalMapping.utf8.count,
                   s.decomposedStringWithCanonicalMapping.utf8.count)
    }

    private static func truncated(_ s: String, toBytes limit: Int) -> String {
        guard byteCount(s) > limit else { return s }
        var bytes = 0
        let kept = s.prefix { ch in
            bytes += byteCount(ch)
            return bytes <= limit
        }
        return String(kept).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
