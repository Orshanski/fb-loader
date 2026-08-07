import Foundation

/// Structured representation of one INP record (one book).
/// Field references match the order in `INPXFieldIndex`.
nonisolated struct INPRecord {
    let authorField: String
    let genreField: String
    let title: String
    let seriesName: String
    let seriesNum: Int16?
    let fileBaseName: String      // libid as string, used as filename inside zip
    let size: Int32
    let libid: Int32
    let deleted: Bool
    let format: String
    /// Полночь дня, записанного в INPX строкой `YYYY-MM-DD`; `nil`, если
    /// поля не было или оно не разобралось.
    let dateAdded: Date?
    let language: String
}

nonisolated enum INPRecordParser {
    static func parse(line: String, fieldIndex: INPXFieldIndex) -> INPRecord? {
        if line.isEmpty { return nil }
        let parts = line.split(separator: "\u{04}", omittingEmptySubsequences: false)
        func at(_ i: Int) -> String {
            i >= 0 && i < parts.count
                ? String(parts[i]).trimmingCharacters(in: .whitespaces)
                : ""
        }
        let author = at(fieldIndex.author)
        let genre = at(fieldIndex.genre)
        let title = at(fieldIndex.title)
        let seriesName = at(fieldIndex.series)
        let seriesNumStr = at(fieldIndex.seriesNum)
        let file = at(fieldIndex.file)
        let sizeStr = at(fieldIndex.size)
        let libidStr = at(fieldIndex.libid)
        let delStr = at(fieldIndex.deleted)
        let format = at(fieldIndex.format)
        let dateStr = at(fieldIndex.date)
        var language = at(fieldIndex.language)
        if language.count > 2 {
            language = String(language.prefix(2))
        }

        return INPRecord(
            authorField: author,
            genreField: genre,
            title: title,
            seriesName: seriesName,
            seriesNum: Int16(seriesNumStr),
            fileBaseName: file,
            size: Int32(sizeStr) ?? 0,
            libid: Int32(libidStr) ?? 0,
            deleted: (Int(delStr) ?? 0) > 0,
            format: format,
            dateAdded: parseDate(dateStr),
            language: language
        )
    }

    /// `YYYY-MM-DD` → полночь этого дня в календаре пользователя.
    /// Тот же календарь потом строит границы фильтра, поэтому книга
    /// граничного дня попадает в диапазон точно.
    private static func parseDate(_ s: String) -> Date? {
        guard s.count == 10 else { return nil }
        let comps = s.split(separator: "-")
        guard comps.count == 3,
              let y = Int(comps[0]), let m = Int(comps[1]), let d = Int(comps[2]),
              y > 0, (1...12).contains(m), (1...31).contains(d) else {
            return nil
        }
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d
        return Calendar.current.date(from: dc)
    }
}
