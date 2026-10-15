import Foundation
import Testing
@testable import FB_Loader

@Suite("INPRecordParser")
struct INPRecordParserTests {
    private let sep = "\u{04}"

    @Test("parses a complete record with default field layout")
    func defaultLayout() throws {
        let line = [
            "Толстой,Лев,Николаевич",         // AUTHOR (0)
            "prose_classic",                  // GENRE  (1)
            "Война и мир",                     // TITLE  (2)
            "Великие романы",                  // SERIES (3)
            "1",                              // SERNO  (4)
            "12345",                          // FILE   (5)
            "987654",                         // SIZE   (6)
            "12345",                          // LIBID  (7)
            "0",                              // DEL    (8)
            "fb2",                            // EXT    (9)
            "2010-05-15",                     // DATE   (10)
            "ru",                             // LANG   (11)
        ].joined(separator: sep)
        let r = try #require(INPRecordParser.parse(line: line, fieldIndex: .defaults))
        #expect(r.title == "Война и мир")
        #expect(r.libid == 12345)
        #expect(r.size == 987654)
        #expect(r.format == "fb2")
        #expect(r.deleted == false)
        #expect(r.language == "ru")
        #expect(r.seriesName == "Великие романы")
        #expect(r.seriesNum == 1)
        // Дата — полночь своего дня в календаре пользователя, поэтому
        // сверяем компонентами, а не `.description` (тот печатает UTC и в
        // зоне со смещением показал бы соседний день).
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: try #require(r.dateAdded))
        #expect(comps.year == 2010)
        #expect(comps.month == 5)
        #expect(comps.day == 15)
        #expect(comps.hour == 0)
        #expect(comps.minute == 0)
        #expect(r.authorField == "Толстой,Лев,Николаевич")
        #expect(r.genreField == "prose_classic")
    }

    @Test("DEL=1 marks the record as deleted")
    func deleted() throws {
        let line = "Author,,\u{04}\u{04}T\u{04}\u{04}\u{04}1\u{04}1\u{04}1\u{04}1\u{04}fb2\u{04}\u{04}ru"
        let r = try #require(INPRecordParser.parse(line: line, fieldIndex: .defaults))
        #expect(r.deleted == true)
    }

    @Test("language is truncated to 2 characters (matching freeLib)")
    func languageTruncation() throws {
        // Some INPX have "ru-RU" or longer; freeLib uses .left(2).
        let parts = ["A,B,C","g","T","","","1","1","1","0","fb2","","ru-RU"]
        let line = parts.joined(separator: sep)
        let r = try #require(INPRecordParser.parse(line: line, fieldIndex: .defaults))
        #expect(r.language == "ru")
    }

    @Test("код языка в нижнем регистре: «RU» и «ru» — один язык")
    func languageLowercased() throws {
        let r = try #require(INPRecordParser.parse(line: INPXFixture.line(libid: "5", lang: "RU"),
                                                   fieldIndex: .defaults))
        #expect(r.language == "ru")
    }

    @Test("returns nil for empty line")
    func empty() {
        #expect(INPRecordParser.parse(line: "", fieldIndex: .defaults) == nil)
    }

    @Test("строка-мусор без полей — не книга")
    func garbageLine() {
        #expect(INPRecordParser.parse(line: "обрывок строки", fieldIndex: .defaults) == nil)
    }

    @Test("LIBID ноль, отрицательный или не число — не книга")
    func invalidLibid() {
        for libid in ["0", "-5", "abc"] {
            let line = INPXFixture.line(file: "x", libid: libid)
            #expect(INPRecordParser.parse(line: line, fieldIndex: .defaults) == nil, "libid=\(libid)")
        }
    }

    @Test("пустой LIBID — берётся числовой FILE, как у freeLib")
    func libidFallsBackToFile() throws {
        let line = INPXFixture.line(file: "777", libid: "")
        let r = try #require(INPRecordParser.parse(line: line, fieldIndex: .defaults))
        #expect(r.libid == 777)
    }

    @Test("пустое название — не книга")
    func emptyTitle() {
        let line = INPXFixture.line(title: "  ", libid: "5")
        #expect(INPRecordParser.parse(line: line, fieldIndex: .defaults) == nil)
    }

    @Test("несуществующая дата — нет даты, а не соседний месяц")
    func invalidDate() throws {
        let line = INPXFixture.line(libid: "5", date: "2015-02-31")
        let r = try #require(INPRecordParser.parse(line: line, fieldIndex: .defaults))
        #expect(r.dateAdded == nil)
    }

    @Test("FILE, отличный от LIBID, сохраняется как имя файла в архиве")
    func archiveFileName() throws {
        let custom = try #require(INPRecordParser.parse(
            line: INPXFixture.line(file: "book-5", libid: "5"), fieldIndex: .defaults))
        #expect(custom.archiveFileName == "book-5")
        let same = try #require(INPRecordParser.parse(
            line: INPXFixture.line(libid: "5"), fieldIndex: .defaults))
        #expect(same.archiveFileName == nil)
    }

    @Test("формат: fb2 или пусто — FB2, остальное — нет")
    func isFB2() throws {
        for (ext, expected) in [("fb2", true), ("FB2", true), ("", true), ("pdf", false), ("djvu", false)] {
            let r = try #require(INPRecordParser.parse(
                line: INPXFixture.line(libid: "5", ext: ext), fieldIndex: .defaults))
            #expect(r.isFB2 == expected, "ext=\(ext)")
        }
    }
}
