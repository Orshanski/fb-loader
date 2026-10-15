import Testing
import Foundation
@testable import FB_Loader

@Suite("INPXImporter")
struct INPXImporterTests {
    @Test("parses tiny.inpx into expected catalog")
    func parsesTiny() throws {
        let url = try #require(TestBundleAnchor.bundle
            .url(forResource: "tiny", withExtension: "inpx"))
        let dict = try GenreDictionary.loadFromBundle()
        let lib = try INPXImporter.parse(inpxURL: url, genres: dict)
        #expect(lib.books.count == 2)
        #expect(lib.archives == ["lib-001"])
        #expect(lib.inpxVersion == "20260301")

        // Authors: Толстой + Дяченко(М) + Дяченко(С) + Олди = 4 (or 3 if Дяченки dedup —
        // they are different middleNames, so distinct → 4).
        #expect(lib.authors.count == 4)
        // Series: "Великие романы" + "Большая серия" = 2.
        #expect(lib.series.count == 2)

        let bookByLibid = Dictionary(uniqueKeysWithValues: lib.books.map { ($0.libid, $0) })
        let warAndPeace = try #require(bookByLibid[100001])
        #expect(warAndPeace.title == "Война и мир")
        #expect(warAndPeace.authorIDs.count == 1)

        let rubezh = try #require(bookByLibid[200001])
        #expect(rubezh.title == "Рубеж. Пентакль")
        #expect(rubezh.authorIDs.count == 3)
        #expect(rubezh.size == 6400838)
    }

    private func importLines(_ lines: [String], lineEnding: String = "\r\n") throws -> Library {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try INPXFixture.make(in: dir, lines: lines, lineEnding: lineEnding)
        return try INPXImporter.parse(inpxURL: url, genres: GenreDictionary.loadFromBundle())
    }

    @Test("CRLF и LF дают одинаковый каталог", arguments: ["\r\n", "\n"])
    func lineEndings(_ ending: String) throws {
        let lib = try importLines([INPXFixture.line(libid: "1"),
                                   INPXFixture.line(title: "Анна Каренина", libid: "2")],
                                  lineEnding: ending)
        #expect(lib.books.map(\.libid) == [1, 2])
    }

    @Test("битые строки пропускаются, остальные книги на месте")
    func garbageLinesSkipped() throws {
        let lib = try importLines([INPXFixture.line(libid: "1"),
                                   "обрывок",
                                   INPXFixture.line(title: "", libid: "2"),
                                   INPXFixture.line(libid: "0"),
                                   INPXFixture.line(libid: "3")])
        #expect(lib.books.map(\.libid) == [1, 3])
    }

    @Test("повтор LIBID — остаётся первая запись")
    func duplicateLibidSkipped() throws {
        let lib = try importLines([INPXFixture.line(title: "Первая", libid: "1"),
                                   INPXFixture.line(title: "Вторая", libid: "1")])
        #expect(lib.books.map(\.title) == ["Первая"])
    }

    @Test("книги не в FB2 не импортируются")
    func nonFB2Skipped() throws {
        let lib = try importLines([INPXFixture.line(libid: "1"),
                                   INPXFixture.line(libid: "2", ext: "pdf")])
        #expect(lib.books.map(\.libid) == [1])
    }

    @Test("незнакомый жанр попадает в каталог под своим кодом (спека §7)")
    func unknownGenreInLibrary() throws {
        let lib = try importLines([INPXFixture.line(genre: "sf_litrpg_xyz:", libid: "1")])
        let gid = try #require(lib.books.first?.genreIDs.first)
        #expect(lib.genreByID[gid]?.name == "sf_litrpg_xyz")
        #expect(lib.sidebarGenres.contains { $0.id == gid })
    }

    @Test("имя файла в архиве — из FILE")
    func archiveEntryName() throws {
        let lib = try importLines([INPXFixture.line(file: "book-1", libid: "1"),
                                   INPXFixture.line(libid: "2")])
        #expect(lib.books.map(\.archiveEntryName) == ["book-1.fb2", "2.fb2"])
    }

    @Test("авторы: регистр и ё не ломают порядок")
    func authorOrder() throws {
        let lib = try importLines([INPXFixture.line(author: "Яковлев,Пётр,:", libid: "1"),
                                   INPXFixture.line(author: "Ёлкин,Иван,:", libid: "2"),
                                   INPXFixture.line(author: "де Голль,Шарль,:", libid: "3"),
                                   INPXFixture.line(author: "Абрамов,Фёдор,:", libid: "4")])
        #expect(lib.authors.map(\.lastName) == ["Абрамов", "де Голль", "Ёлкин", "Яковлев"])
    }

    @Test("сверхдлинное название обрезается, каталог сохраняется в кэш")
    func hugeTitleClamped() throws {
        let lib = try importLines([INPXFixture.line(title: String(repeating: "Щ", count: 70_000), libid: "1")])
        let title = try #require(lib.books.first?.title)
        #expect(title.utf8.count <= INPXImporter.maxStringBytes)
        #expect(throws: Never.self) {
            _ = try LibraryBinaryCodec.encode(lib, sourceKey: Data(count: 32))
        }
    }

    @Test("пустой AUTHOR в начале строки — книга под «(Без автора)», поля не съезжают")
    func emptyFirstField() throws {
        let lib = try importLines([INPXFixture.line(author: "", libid: "1")])
        let book = try #require(lib.books.first)
        #expect(book.libid == 1)
        #expect(book.title == "Война и мир")
        #expect(book.authorIDs == [Author.unknownID])
    }

    @Test("DEL=1 не попадает в каталог")
    func deletedSkipped() throws {
        let lib = try importLines([INPXFixture.line(libid: "1"),
                                   INPXFixture.line(libid: "2", deleted: "1")])
        #expect(lib.books.map(\.libid) == [1])
    }

    @Test("переставленные поля из STRUCTURE.INFO")
    func reorderedStructure() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let line = ["42", "Пикник на обочине", "Стругацкий,Аркадий,Натанович:",
                    "sf_social:", "picnic", "fb2", "0", "ru"].joined(separator: "\u{04}")
        let url = try INPXFixture.make(in: dir, lines: [line],
                                       structure: "LIBID;TITLE;AUTHOR;GENRE;FILE;EXT;DEL;LANG")
        let lib = try INPXImporter.parse(inpxURL: url, genres: GenreDictionary.loadFromBundle())
        let book = try #require(lib.books.first)
        #expect(book.libid == 42)
        #expect(book.title == "Пикник на обочине")
        #expect(book.archiveEntryName == "picnic.fb2")
        #expect(lib.authorByID[book.authorIDs[0]]?.lastName == "Стругацкий")
    }

    @Test("сверхдлинное имя файла — запись отбрасывается: обрезанное в архиве не найдётся")
    func hugeFileNameSkipped() throws {
        let lib = try importLines([INPXFixture.line(file: String(repeating: "f", count: 5000), libid: "1"),
                                   INPXFixture.line(libid: "2")])
        #expect(lib.books.map(\.libid) == [2])
    }

    @Test("серии: регистр и диакритика не ломают порядок")
    func seriesOrder() throws {
        let lib = try importLines([INPXFixture.line(series: "Zebra", libid: "1"),
                                   INPXFixture.line(series: "école", libid: "2"),
                                   INPXFixture.line(series: "apple", libid: "3")])
        #expect(lib.series.map(\.name) == ["apple", "école", "Zebra"])
    }

    @Test("имя архива — только последний компонент имени .inp")
    func archiveBaseNameStripsPath() {
        #expect(INPXImporter.archiveBaseName(forInp: "fb2-000024-030559.inp") == "fb2-000024-030559")
        #expect(INPXImporter.archiveBaseName(forInp: "../../etc/x.inp") == "x")
        #expect(INPXImporter.archiveBaseName(forInp: "sub/dir/y.inp") == "y")
    }
}