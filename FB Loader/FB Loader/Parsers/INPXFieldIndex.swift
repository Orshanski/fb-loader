import Foundation

/// Mapping of logical INP fields to their column index in a record.
/// Defaults match freeLib's hard-coded fallback (importthread.cpp:685-722).
/// Real INPX archives override this via STRUCTURE.INFO.
///
/// Recognised tokens: AUTHOR, GENRE, TITLE, SERIES, SERNO, FILE, SIZE, LIBID,
/// DEL, EXT, DATE, LANG. Out of scope (not stored in `Book`): STARS, KEYWORDS,
/// FOLDER, TAG, TAGSERIES, TAGAUTHOR — silently ignored.
struct INPXFieldIndex: Sendable, Equatable {
    var author: Int
    var genre: Int
    var title: Int
    var series: Int
    var seriesNum: Int
    var file: Int
    var size: Int
    var libid: Int
    var deleted: Int
    var format: Int
    var date: Int
    var language: Int

    static let defaults = INPXFieldIndex(
        author: 0, genre: 1, title: 2, series: 3, seriesNum: 4,
        file: 5, size: 6, libid: 7, deleted: 8, format: 9, date: 10, language: 11
    )

    static func fromStructureInfo(_ text: String) -> INPXFieldIndex {
        // STRUCTURE.INFO may begin with a non-field header line (e.g.
        // "INPX VERSION;1.0") followed by the field row. freeLib iterates all
        // lines and accumulates positions (importthread.cpp:737-782). If no
        // recognised token is ever seen, fall back to defaults — that's a
        // header-only or malformed file, and silently returning all -1 would
        // drop the entire archive.
        var idx = INPXFieldIndex(
            author: -1, genre: -1, title: -1, series: -1, seriesNum: -1,
            file: -1, size: -1, libid: -1, deleted: -1, format: -1, date: -1, language: -1
        )
        var matched = false
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            for (i, token) in line.uppercased().split(separator: ";").enumerated() {
                switch token {
                case "AUTHOR":   idx.author = i;     matched = true
                case "GENRE":    idx.genre = i;      matched = true
                case "TITLE":    idx.title = i;      matched = true
                case "SERIES":   idx.series = i;     matched = true
                case "SERNO":    idx.seriesNum = i;  matched = true
                case "FILE":     idx.file = i;       matched = true
                case "SIZE":     idx.size = i;       matched = true
                case "LIBID":    idx.libid = i;      matched = true
                case "DEL":      idx.deleted = i;    matched = true
                case "EXT":      idx.format = i;     matched = true
                case "DATE":     idx.date = i;       matched = true
                case "LANG":     idx.language = i;   matched = true
                default:         break
                }
            }
        }
        return matched ? idx : .defaults
    }
}
