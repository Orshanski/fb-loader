import Foundation
import Testing
@testable import FB_Loader

@Suite("INPRecordParser")
struct INPRecordParserTests {
    private let SEP = "\u{04}"

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
        ].joined(separator: SEP)
        let r = try #require(INPRecordParser.parse(line: line, fieldIndex: .defaults))
        #expect(r.title == "Война и мир")
        #expect(r.libid == 12345)
        #expect(r.size == 987654)
        #expect(r.format == "fb2")
        #expect(r.deleted == false)
        #expect(r.language == "ru")
        #expect(r.seriesName == "Великие романы")
        #expect(r.seriesNum == 1)
        #expect(r.dateAdded?.description.starts(with: "2010-05-15") ?? false)
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
        let line = parts.joined(separator: SEP)
        let r = try #require(INPRecordParser.parse(line: line, fieldIndex: .defaults))
        #expect(r.language == "ru")
    }

    @Test("returns nil for empty line")
    func empty() {
        #expect(INPRecordParser.parse(line: "", fieldIndex: .defaults) == nil)
    }
}
