import Testing
@testable import FB_Loader

@Suite("INPXFieldIndex")
struct INPXFieldIndexTests {
    @Test("default layout matches freeLib defaults")
    func defaults() {
        let idx = INPXFieldIndex.defaults
        #expect(idx.author == 0)
        #expect(idx.genre == 1)
        #expect(idx.title == 2)
        #expect(idx.series == 3)
        #expect(idx.seriesNum == 4)
        #expect(idx.file == 5)
        #expect(idx.size == 6)
        #expect(idx.libid == 7)
        #expect(idx.deleted == 8)
        #expect(idx.format == 9)
        #expect(idx.date == 10)
        #expect(idx.language == 11)
    }

    @Test("parses a STRUCTURE.INFO with semicolon-separated headers")
    func parsesStructure() {
        let info = "AUTHOR;GENRE;TITLE;SERIES;SERNO;FILE;SIZE;LIBID;DEL;EXT;DATE;LANG\n"
        let idx = INPXFieldIndex.fromStructureInfo(info)
        #expect(idx.author == 0)
        #expect(idx.title == 2)
        #expect(idx.libid == 7)
        #expect(idx.language == 11)
    }

    @Test("STRUCTURE.INFO with reordered fields")
    func reordered() {
        let info = "TITLE;AUTHOR;FILE;SIZE;LIBID;DEL;EXT;DATE;LANG;GENRE;SERIES;SERNO\n"
        let idx = INPXFieldIndex.fromStructureInfo(info)
        #expect(idx.title == 0)
        #expect(idx.author == 1)
        #expect(idx.genre == 9)
    }
}
