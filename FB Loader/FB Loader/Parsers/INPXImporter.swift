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

    static func parse(
        inpxURL: URL,
        genres: GenreDictionary,
        onStatus: (@Sendable (String) -> Void)? = nil,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) throws -> Library {
        onStatus?("Хеш INPX-файла…")
        let inpxHash = try SHA256.hash(ofFileAt: inpxURL)

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

            // archiveIndex maps to the corresponding .zip filename without extension —
            // exactly as freeLib does (importthread.cpp:250 replaces ".inp" with ".zip").
            let archBase = (name as NSString).deletingPathExtension
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
                if rec.deleted { continue }

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
                for t in triples {
                    if INPAuthorParser.isUnknown(
                        lastName: t.lastName, firstName: t.firstName, middleName: t.middleName) {
                        continue
                    }
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
                if !rec.seriesName.isEmpty {
                    if let existing = seriesIDs[rec.seriesName] {
                        seriesID = existing
                    } else {
                        let newID = Int32(series.count + 1) // 0 reserved for "no series"
                        series.append(Series(id: newID, name: rec.seriesName))
                        seriesIDs[rec.seriesName] = newID
                        seriesID = newID
                    }
                }

                books.append(Book(
                    libid: rec.libid,
                    title: rec.title,
                    authorIDs: bookAuthorIDs,
                    seriesID: seriesID,
                    seriesNum: rec.seriesNum,
                    genreIDs: genreIDs,
                    language: rec.language,
                    archiveIndex: archIdx,
                    size: rec.size,
                    dateAdded: rec.dateAdded
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
        let sortedAuthors = visibleAuthors.sorted { a, b in
            if a.id == Author.unknownID { return false }
            if b.id == Author.unknownID { return true }
            return (a.lastName, a.firstName, a.middleName)
                 < (b.lastName, b.firstName, b.middleName)
        }
        let sortedSeries = series.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return Library(
            inpxHash: inpxHash,
            inpxVersion: version,
            archives: archiveNames,
            authors: sortedAuthors,
            series: sortedSeries,
            genres: genres.allGenres,
            books: books,
            onStatus: onStatus
        )
    }
}
