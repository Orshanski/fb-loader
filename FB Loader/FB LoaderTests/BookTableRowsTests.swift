import Testing
import Foundation
@testable import FB_Loader

@Suite("BookTableRows")
struct BookTableRowsTests {
    private func book(_ libid: Int32, series: Int32? = nil, num: Int16? = nil) -> Book {
        Book(libid: libid, title: "B\(libid)", authorIDs: [1], seriesID: series, seriesNum: num,
             genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAdded: nil)
    }

    private func library(_ series: [Series]) -> Library {
        Library(inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
                authors: [Author(id: 1, lastName: "X", firstName: "", middleName: "")],
                series: series, genres: [], books: [])
    }

    /// Книга вне серии — «libid», книга серии — «  libid», заголовок — «[имя count]».
    private func describe(_ r: BookTableRows) -> [String] {
        r.rows.map {
            switch $0 {
            case .book(let b, let inSeries): return inSeries ? "  \(b.libid)" : "\(b.libid)"
            case .seriesHeader(let s, let count): return "[\(s.name) \(count)]"
            }
        }
    }

    @Test("без серий — книги в порядке выборки, без заголовков")
    func noSeries() {
        let r = BookTableRows.build(books: [book(3), book(1), book(2)], library: library([]))
        #expect(describe(r) == ["3", "1", "2"])
    }

    @Test("книги без серии выше всех серий, count — книг серии в выборке")
    func looseFirst() {
        let lib = library([Series(id: 1, name: "Альфа")])
        let r = BookTableRows.build(
            books: [book(10, series: 1, num: 1), book(20), book(11, series: 1, num: 2), book(21)],
            library: lib)
        #expect(describe(r) == ["20", "21", "[Альфа 2]", "  10", "  11"])
    }

    @Test("серии по имени, одинаковые имена — по id, неизвестная — «?»")
    func seriesOrder() {
        let lib = library([Series(id: 2, name: "Б"), Series(id: 3, name: "А"), Series(id: 1, name: "А")])
        let r = BookTableRows.build(
            books: [book(1, series: 2), book(2, series: 3), book(3, series: 1), book(4, series: 9)],
            library: lib)
        #expect(describe(r) == ["[? 1]", "  4", "[А 1]", "  3", "[А 1]", "  2", "[Б 1]", "  1"])
    }

    @Test("внутри серии по номеру, без номера — в конце в порядке выборки")
    func seriesNumbers() {
        let lib = library([Series(id: 1, name: "S")])
        let r = BookTableRows.build(
            books: [book(1, series: 1, num: 3), book(2, series: 1), book(3, series: 1, num: 1),
                    book(4, series: 1), book(5, series: 1, num: 2)],
            library: lib)
        #expect(describe(r) == ["[S 5]", "  3", "  5", "  1", "  2", "  4"])
    }

    @Test("row(ofLibid:), isBook, libid(at:), book(at:)")
    func lookup() {
        let lib = library([Series(id: 1, name: "Альфа")])
        let r = BookTableRows.build(
            books: [book(10, series: 1, num: 1), book(20), book(11, series: 1, num: 2)],
            library: lib)
        // 0: 20, 1: [Альфа 2], 2: 10, 3: 11
        #expect(r.row(ofLibid: 20) == 0)
        #expect(r.row(ofLibid: 11) == 3)
        #expect(r.row(ofLibid: 99) == nil)
        #expect(r.isBook(0))
        #expect(!r.isBook(1))
        #expect(!r.isBook(-1))
        #expect(!r.isBook(4))
        #expect(r.libid(at: 1) == nil)
        #expect(r.libid(at: 2) == 10)
        #expect(r.book(at: 99) == nil)
        #expect(r.count == 4)
    }

    @Test("дубль libid — индекс на первую строку")
    func duplicateLibid() {
        let b = book(1)
        let r = BookTableRows(rows: [.book(b, inSeries: false), .book(b, inSeries: true)])
        #expect(r.row(ofLibid: 1) == 0)
    }

    @Test("пустая выборка — пустые строки")
    func empty() {
        let r = BookTableRows.build(books: [], library: library([]))
        #expect(r.rows.isEmpty)
        #expect(r.count == 0)
        #expect(BookTableRows.empty.count == 0)
    }

    /// 0: книга 1, 1: [S], 2: книга 2, 3: книга 3, 4: [T], 5: книга 4.
    private var rowsA: BookTableRows {
        BookTableRows(rows: [
            .book(book(1), inSeries: false),
            .seriesHeader(Series(id: 1, name: "S"), count: 2),
            .book(book(2, series: 1), inSeries: true),
            .book(book(3, series: 1), inSeries: true),
            .seriesHeader(Series(id: 2, name: "T"), count: 1),
            .book(book(4, series: 2), inSeries: true),
        ])
    }

    /// 0: [S], 1: книга 1, 2: книга 2.
    private var rowsB: BookTableRows {
        BookTableRows(rows: [
            .seriesHeader(Series(id: 1, name: "S"), count: 2),
            .book(book(1, series: 1), inSeries: true),
            .book(book(2, series: 1), inSeries: true),
        ])
    }

    @Test("клавиатура: заголовок ниже текущей — следующая книга, выше — предыдущая")
    func keyboardSkipsHeader() {
        #expect(rowsA.resolveSelection(proposed: 4, current: 3, byKeyboard: true) == 5)
        #expect(rowsA.resolveSelection(proposed: 4, current: 5, byKeyboard: true) == 3)
    }

    @Test("клавиатура: заголовок в строке 0 без текущей — строка 1; ↑ на первой книге — текущая")
    func keyboardEdges() {
        #expect(rowsB.resolveSelection(proposed: 0, current: nil, byKeyboard: true) == 1)
        #expect(rowsB.resolveSelection(proposed: 0, current: 1, byKeyboard: true) == 1)
    }

    @Test("мышь на заголовке — текущая; пустое — текущая; книга — книга")
    func mouseAndEmpty() {
        #expect(rowsA.resolveSelection(proposed: 1, current: 3, byKeyboard: false) == 3)
        #expect(rowsA.resolveSelection(proposed: 1, current: nil, byKeyboard: false) == nil)
        #expect(rowsA.resolveSelection(proposed: nil, current: 2, byKeyboard: false) == 2)
        #expect(rowsA.resolveSelection(proposed: nil, current: 2, byKeyboard: true) == 2)
        #expect(rowsA.resolveSelection(proposed: 5, current: 0, byKeyboard: false) == 5)
        #expect(rowsA.resolveSelection(proposed: 5, current: 0, byKeyboard: true) == 5)
        #expect(rowsA.resolveSelection(proposed: 99, current: 0, byKeyboard: true) == 0)
    }

    @Test("selectionChangedExternally: выделение сдвинуто, только если книга есть в строках и не под выделением")
    func externalSelection() {
        #expect(selectionChangedExternally(currentRow: -1, targetRow: 3))
        #expect(selectionChangedExternally(currentRow: 1, targetRow: 3))
        #expect(!selectionChangedExternally(currentRow: 3, targetRow: 3))
        #expect(!selectionChangedExternally(currentRow: 1, targetRow: nil))
    }

    @Test("scrollTarget: нет выбранной или нет в строках — к началу; книга — строка и заголовок серии")
    func scrollTargets() {
        #expect(rowsA.scrollTarget(selectedLibid: nil) == .top)
        #expect(rowsA.scrollTarget(selectedLibid: 99) == .top)
        #expect(rowsA.scrollTarget(selectedLibid: 1) == .row(0, header: nil))
        #expect(rowsA.scrollTarget(selectedLibid: 2) == .row(2, header: 1))
        #expect(rowsA.scrollTarget(selectedLibid: 3) == .row(3, header: nil))
        #expect(rowsB.scrollTarget(selectedLibid: 1) == .row(1, header: 0))
    }
}
