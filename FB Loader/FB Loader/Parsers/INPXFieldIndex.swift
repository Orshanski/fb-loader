import Foundation

/// Mapping of logical INP fields to their column index in a record.
/// Defaults match freeLib's hard-coded fallback (importthread.cpp:685-722).
/// Real INPX archives override this via STRUCTURE.INFO.
struct INPXFieldIndex: Sendable {
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
        // STRUCTURE.INFO format: header line(s), each is `;`-separated tokens (uppercase).
        // We only honour the first non-empty line.
        var idx = INPXFieldIndex(
            author: -1, genre: -1, title: -1, series: -1, seriesNum: -1,
            file: -1, size: -1, libid: -1, deleted: -1, format: -1, date: -1, language: -1
        )
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            for (i, token) in line.uppercased().split(separator: ";").enumerated() {
                switch token {
                case "AUTHOR":   idx.author = i
                case "GENRE":    idx.genre = i
                case "TITLE":    idx.title = i
                case "SERIES":   idx.series = i
                case "SERNO":    idx.seriesNum = i
                case "FILE":     idx.file = i
                case "SIZE":     idx.size = i
                case "LIBID":    idx.libid = i
                case "DEL":      idx.deleted = i
                case "EXT":      idx.format = i
                case "DATE":     idx.date = i
                case "LANG":     idx.language = i
                default:         break
                }
            }
            return idx
        }
        return .defaults
    }
}
