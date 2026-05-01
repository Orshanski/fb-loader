import Foundation
import ZIPFoundation

/// Imports an INPX archive into an in-memory `Library`.
/// Skips records with DEL=1.
/// Author dedup is by (lastName, firstName, middleName) tuple.
/// Empty/unknown authors are mapped to the synthetic `Author.unknown`.
nonisolated enum INPXImporter {
    enum ImportError: Error {
        /// Wraps the actual ZIPFoundation error for diagnostics — never silently lost.
        case cannotOpenArchive(URL, underlying: Error)
        case noVersionInfo
        case tooManyArchives(count: Int)
    }

    /// Cached `CharacterSet` for the line-trim step. Built once and reused across 700k iterations.
    private static let trimSet: CharacterSet = .controlCharacters
        .subtracting(.init(charactersIn: "\u{04}"))

    static func import_(inpxURL: URL, genres: GenreDictionary) throws -> Library {
        let inpxData = try Data(contentsOf: inpxURL)
        let inpxHash = SHA256.hash(of: inpxData)

        let archive: Archive
        do {
            archive = try Archive(data: inpxData, accessMode: .read)
        } catch {
            throw ImportError.cannotOpenArchive(inpxURL, underlying: error)
        }

        // 1. version.info — case-insensitive lookup (some INPX dumps use VERSION.INFO).
        var version = ""
        if let entry = archive.first(where: { $0.path.lowercased() == "version.info" }) {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            version = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw ImportError.noVersionInfo
        }

        // 2. STRUCTURE.INFO (optional) — case-insensitive.
        var fieldIndex = INPXFieldIndex.defaults
        if let entry = archive.first(where: { $0.path.lowercased() == "structure.info" }) {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
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

        for entry in archive {
            let name = entry.path
            guard name.lowercased().hasSuffix(".inp") else { continue }

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

            var inpData = Data()
            _ = try archive.extract(entry) { inpData.append($0) }
            let text = String(decoding: inpData, as: UTF8.self)

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
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

                // Date → days since Book.dateEpoch.
                // `days = 0` is the sentinel for missing/unparseable dates; it
                // collides with a literal 2000-01-01 entry, but real INPX dumps
                // are post-2008 so the conflation is harmless.
                let days: Int32
                if let d = rec.dateAdded {
                    let interval = Int(d.timeIntervalSince(Book.dateEpoch) / 86400)
                    days = Int32(interval)
                } else {
                    days = 0
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
                    dateAddedDays: days
                ))
            }
        }

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
            books: books
        )
    }
}
