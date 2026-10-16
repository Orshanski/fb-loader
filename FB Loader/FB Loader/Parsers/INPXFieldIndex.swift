import Foundation

/// Logical INP field → column index. Defaults match freeLib's fallback (importthread.cpp:685-722);
/// STRUCTURE.INFO overrides them. Tokens not stored in `Book` (STARS, KEYWORDS, FOLDER, TAG*) are ignored.
nonisolated struct INPXFieldIndex: Sendable, Equatable {
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
        // STRUCTURE.INFO may begin with a header line ("INPX VERSION;1.0"); freeLib scans all lines
        // (importthread.cpp:737-782). No recognised token → defaults, else every field is -1 and the archive is dropped.
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
