import Foundation

/// Imports an INPX archive into an in-memory `Library`.
/// Skips records with DEL=1.
/// Author dedup is by (lastName, firstName, middleName) tuple.
/// Empty/unknown authors are mapped to the synthetic `Author.unknown`.
nonisolated enum INPXImporter {
    enum ImportError: Error {
        /// Wraps the underlying central-directory parse / decompression error.
        case cannotOpenArchive(URL, underlying: Error)
        case noVersionInfo
        case tooManyArchives(count: Int)
    }

    /// Cached `CharacterSet` for the line-trim step. Built once and reused across 700k iterations.
    private static let trimSet: CharacterSet = .controlCharacters
        .subtracting(.init(charactersIn: "\u{04}"))

    /// Emit a progress callback every N parsed (non-deleted) books, plus once
    /// at the boundary between .inp files. 200 keeps the UI ticking even on
    /// the first small .inp (which may have <1000 books).
    private static let progressEveryNBooks = 200

    /// Поднимать при любой правке разбора INPX (здесь, в парсерах, в синтетических
    /// жанрах) — иначе у пользователей останется кэш от старого кода.
    static let logicVersion: UInt16 = 2

    /// Длина строки в кэше — 16 бит; одна кривая запись иначе ломает запись кэша.
    static let maxStringBytes = 4096

    private static func clamped(_ s: String) -> String {
        guard s.utf8.count > maxStringBytes else { return s }
        var out = ""
        var bytes = 0
        for ch in s {
            let n = ch.utf8.count
            if bytes + n > maxStringBytes { break }
            out.append(ch)
            bytes += n
        }
        return out
    }

    /// Не `localizedCompare`: на 167k авторов он занимает секунды.
    private static func sortKey(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Как freeLib (importthread.cpp:250).
    static func archiveBaseName(forInp name: String) -> String {
        ((name as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func parse(
        inpxURL: URL,
        inpxHash knownHash: Data? = nil,
        genres: GenreDictionary,
        onStatus: (@Sendable (String) -> Void)? = nil,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) throws -> Library {
        let inpxHash: Data
        if let knownHash {
            inpxHash = knownHash
        } else {
            onStatus?("Хеш INPX-файла…")
            inpxHash = try SHA256.hash(ofFileAt: inpxURL)
        }

        onStatus?("Чтение центральной директории INPX…")
        let index: ZipCentralDirectory.Index
        do {
            index = try ZipCentralDirectory.readIndex(of: inpxURL)
        } catch {
            throw ImportError.cannotOpenArchive(inpxURL, underlying: error)
        }

        // INPX file names are usually lowercase but some dumps use VERSION.INFO etc.
        // Build a lowercase-keyed lookup once.
        var byLowercaseName: [String: ZipCentralDirectory.Entry] = [:]
        byLowercaseName.reserveCapacity(index.entries.count)
        for (name, entry) in index.entries {
            byLowercaseName[name.lowercased()] = entry
        }

        // 1. version.info
        var version = ""
        if let versionEntry = byLowercaseName["version.info"] {
            let data = try ZipCentralDirectory.extract(versionEntry, from: inpxURL)
            version = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw ImportError.noVersionInfo
        }

        // 2. STRUCTURE.INFO (optional)
        var fieldIndex = INPXFieldIndex.defaults
        if let structureEntry = byLowercaseName["structure.info"] {
            let data = try ZipCentralDirectory.extract(structureEntry, from: inpxURL)
            fieldIndex = INPXFieldIndex.fromStructureInfo(
                String(decoding: data, as: UTF8.self))
        }

        // 3. Iterate .inp files, build catalog.
        var archiveNames: [String] = []
        var archiveIndexByName: [String: Int16] = [:]
        var authorIDs: [INPAuthorParser.Triple: Int32] = [:]
        var authors: [Author] = []
        var seriesIDs: [String: Int32] = [:]
        var series: [Series] = []
        var books: [Book] = []
        var seenLibids = Set<Int32>()
        var skippedDeleted = 0, skippedNotFB2 = 0, skippedDuplicate = 0, skippedFileName = 0

        // Reserve slot 0 for the synthetic "(Без автора)" placeholder.
        // It may be filtered out at the end if no book actually references it.
        authors.append(Author.unknown)

        // Pre-collect .inp entries so we can report "X / N" progress.
        let inpEntries: [ZipCentralDirectory.Entry] = index.entries
            .filter { $0.key.lowercased().hasSuffix(".inp") }
            .values
            .sorted { $0.name < $1.name }
        print("[INPXImporter] start: \(inpEntries.count) .inp files in archive")
        onStatus?("Найдено \(inpEntries.count) .inp файлов")
        var archCounter = 0
        for entry in inpEntries {
            let name = entry.name
            archCounter += 1
            print("[INPXImporter] reading [\(archCounter)/\(inpEntries.count)] \(name)")
            onStatus?("[\(archCounter)/\(inpEntries.count)] \(name)")

            let archBase = archiveBaseName(forInp: name)
            let archIdx: Int16
            if let i = archiveIndexByName[archBase] {
                archIdx = i
            } else {
                let nextIdx = archiveNames.count
                if nextIdx > Int(Int16.max) {
                    throw ImportError.tooManyArchives(count: nextIdx)
                }
                archIdx = Int16(nextIdx)
                archiveIndexByName[archBase] = archIdx
                archiveNames.append(archBase)
            }

            let inpData = try ZipCentralDirectory.extract(entry, from: inpxURL)
            let text = String(decoding: inpData, as: UTF8.self)
            let booksBefore = books.count

            // Records are separated by CRLF in real Flibusta INPX dumps. Swift's
            // String treats "\r\n" as a SINGLE extended grapheme cluster, so
            // `split(separator: "\n")` does NOT find the LF and returns the
            // whole file as one "line" — that's how we ended up with exactly
            // one book per .inp before this fix. Use Character.isNewline,
            // which is true for both bare "\n" and the "\r\n" cluster.
            for line in text.split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline }) {
                let trimmed = String(line).trimmingCharacters(in: trimSet)
                guard let rec = INPRecordParser.parse(line: trimmed, fieldIndex: fieldIndex)
                else { continue }
                if rec.deleted { skippedDeleted += 1; continue }
                if !rec.isFB2 { skippedNotFB2 += 1; continue }
                if let f = rec.archiveFileName, f.utf8.count > maxStringBytes {
                    skippedFileName += 1; continue
                }
                guard seenLibids.insert(rec.libid).inserted else { skippedDuplicate += 1; continue }

                // Genres
                let genreCodes = rec.genreField.split(separator: ":",
                                                      omittingEmptySubsequences: true)
                let genreIDs: [Int16] = genreCodes.compactMap { code in
                    genres.genre(forCode: String(code).trimmingCharacters(in: .whitespaces))?.id
                }

                // Authors
                let triples = INPAuthorParser.parse(rec.authorField)
                    .filter { !($0.lastName.isEmpty && $0.firstName.isEmpty && $0.middleName.isEmpty) }
                var bookAuthorIDs: [Int32] = []
                for raw in triples {
                    if INPAuthorParser.isUnknown(
                        lastName: raw.lastName, firstName: raw.firstName, middleName: raw.middleName) {
                        continue
                    }
                    let t = INPAuthorParser.Triple(lastName: clamped(raw.lastName),
                                                   firstName: clamped(raw.firstName),
                                                   middleName: clamped(raw.middleName))
                    if let existing = authorIDs[t] {
                        bookAuthorIDs.append(existing)
                    } else {
                        let newID = Int32(authors.count)
                        let a = Author(id: newID,
                                       lastName: t.lastName,
                                       firstName: t.firstName,
                                       middleName: t.middleName)
                        authors.append(a)
                        authorIDs[t] = newID
                        bookAuthorIDs.append(newID)
                    }
                }
                if bookAuthorIDs.isEmpty {
                    bookAuthorIDs = [Author.unknownID]
                }

                // Series
                var seriesID: Int32? = nil
                let seriesName = clamped(rec.seriesName)
                if !seriesName.isEmpty {
                    if let existing = seriesIDs[seriesName] {
                        seriesID = existing
                    } else {
                        let newID = Int32(series.count + 1) // 0 reserved for "no series"
                        series.append(Series(id: newID, name: seriesName))
                        seriesIDs[seriesName] = newID
                        seriesID = newID
                    }
                }

                books.append(Book(
                    libid: rec.libid,
                    title: clamped(rec.title),
                    authorIDs: bookAuthorIDs,
                    seriesID: seriesID,
                    seriesNum: rec.seriesNum,
                    genreIDs: genreIDs,
                    language: rec.language,
                    archiveIndex: archIdx,
                    size: rec.size,
                    dateAdded: rec.dateAdded,
                    archiveFileName: rec.archiveFileName
                ))
                if books.count % Self.progressEveryNBooks == 0 {
                    onProgress?(books.count)
                }
            }
            let doneStatus = "[\(archCounter)/\(inpEntries.count)] done — added \(books.count - booksBefore) books, total \(books.count)"
            print("[INPXImporter] \(doneStatus)")
            onStatus?(doneStatus)
            // Per-archive boundary emit — guarantees a UI tick even on tiny .inp files.
            onProgress?(books.count)
        }
        print("[INPXImporter] all .inp files done, total books: \(books.count); building Library…")
        print("[INPXImporter] skipped: deleted \(skippedDeleted), not FB2 \(skippedNotFB2), duplicate LIBID \(skippedDuplicate), file name too long \(skippedFileName)")
        onStatus?("all .inp files done, total books: \(books.count); building Library…")
        // Final emit so the caller's UI ends with the actual total, not the last
        // multiple of `progressEveryNBooks`.
        onProgress?(books.count)

        // Sort authors by lastName, firstName, middleName.
        // The synthetic "(Без автора)" placeholder is included only when at least
        // one book actually references it — clean libraries don't show an empty
        // placeholder. When present, it always goes to the end of the list,
        // following the standard "Other" UX pattern.
        let unknownReferenced = books.contains { $0.authorIDs.contains(Author.unknownID) }
        let visibleAuthors = unknownReferenced
            ? authors
            : authors.filter { $0.id != Author.unknownID }
        let sortedAuthors = visibleAuthors
            .map { a in (a, sortKey(a.lastName), sortKey(a.firstName), sortKey(a.middleName)) }
            .sorted { x, y in
                if x.0.id == Author.unknownID { return false }
                if y.0.id == Author.unknownID { return true }
                return (x.1, x.2, x.3) < (y.1, y.2, y.3)
            }
            .map(\.0)
        let sortedSeries = series
            .map { s in (s, sortKey(s.name)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        return Library(
            inpxHash: inpxHash,
            inpxVersion: version,
            archives: archiveNames,
            authors: sortedAuthors,
            series: sortedSeries,
            genres: genres.libraryGenres,
            books: books,
            onStatus: onStatus
        )
    }
}
