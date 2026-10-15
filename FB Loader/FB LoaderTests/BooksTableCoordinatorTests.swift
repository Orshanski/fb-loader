import AppKit
import Testing
@testable import FB_Loader

@MainActor
final class FakeBooksTableModel: BooksTableModel {
    var selectionWrites: [Int32?] = []
    var selectedBookLibid: Int32? = nil { didSet { selectionWrites.append(selectedBookLibid) } }
    var checkedBookLibids: Set<Int32> = []
    private(set) var dateFilter: DateRangeFilter? = nil
    private(set) var appliedFilters: [DateRangeFilter?] = []
    func applyDateFilter(_ next: DateRangeFilter?) {
        appliedFilters.append(next)
        dateFilter = next
    }
}

nonisolated enum BooksTableFixture {
    static func book(_ libid: Int32, _ title: String, series: Int32? = nil, num: Int16? = nil,
                     genres: [Int16] = []) -> Book {
        Book(libid: libid, title: title, authorIDs: [1], seriesID: series, seriesNum: num,
             genreIDs: genres, language: "ru", archiveIndex: 0, size: 2048, dateAdded: nil)
    }

    static let library = Library(
        inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
        authors: [Author(id: 1, lastName: "X", firstName: "", middleName: "")],
        series: [Series(id: 1, name: "Серия")],
        genres: [Genre(id: 1, code: "sf", name: "Фантастика", parentID: nil),
                 Genre(id: 2, code: "det", name: "Детектив", parentID: nil)],
        books: [])

    /// Строки: 0 «Альфа» (10), 1 «Бета» (11), 2 [Серия 2], 3 «Гамма» (20, №1), 4 «Дельта» (21, №2).
    static let books: [Book] = [
        book(10, "Альфа", genres: [1, 2]), book(11, "Бета"),
        book(20, "Гамма", series: 1, num: 1), book(21, "Дельта", series: 1, num: 2),
    ]
}

/// Таблица в окне (не показанном): клавиатура, `visibleRect` и `row(at:)` работают как в приложении.
@MainActor
final class BooksTableHarness {
    let model = FakeBooksTableModel()
    let exportAction = ExportAction()
    let coordinator: BooksTableRepresentable.Coordinator
    let scrollView: NSScrollView
    let window: NSWindow
    var table: BooksNSTableView { coordinator.tableView! }

    init(books: [Book] = BooksTableFixture.books, context: BooksByContext.Context? = .author(1),
         dates: DateRangeFilter? = nil, selected: Int32? = nil, checked: Set<Int32> = []) {
        model.selectedBookLibid = selected
        model.checkedBookLibids = checked
        coordinator = BooksTableRepresentable.Coordinator(
            model: model, library: BooksTableFixture.library, exportAction: exportAction)
        scrollView = BooksTableRepresentable.makeScrollView(coordinator: coordinator)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                          styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        apply(books: books, context: context, dates: dates)
        model.selectionWrites.removeAll()
    }

    func apply(books: [Book], context: BooksByContext.Context?, dates: DateRangeFilter? = nil) {
        coordinator.apply(rows: BookTableRows.build(books: books, library: BooksTableFixture.library),
                          key: BooksTableKey(context: context, language: "ru", dates: dates),
                          selectedLibid: model.selectedBookLibid, checked: model.checkedBookLibids)
    }

    func select(row: Int) {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    func titleCell(row: Int) -> BookTitleCellView? {
        coordinator.tableView(table, viewFor: table.tableColumn(withIdentifier: BookTableColumnID.title.identifier),
                              row: row) as? BookTitleCellView
    }
}

@Suite("BooksTable coordinator")
@MainActor
struct BooksTableCoordinatorTests {
    @Test("выбор строки книги пользователем пишет libid; два шага — две записи")
    func userSelectionWrites() {
        let h = BooksTableHarness()
        h.select(row: 0)
        h.select(row: 3)
        #expect(h.model.selectionWrites == [10, 20])
    }

    @Test("syncSelection к книге выделяет строку, к отсутствующей снимает; в модель не пишет")
    func syncDoesNotWrite() {
        let h = BooksTableHarness()
        h.coordinator.syncSelection(of: h.table, to: 21)
        #expect(h.table.selectedRow == 4)
        h.coordinator.syncSelection(of: h.table, to: 99)
        #expect(h.table.selectedRow == -1)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("новый ключ без выбранной книги в строках — не пишет, выделения нет")
    func newKeyWithoutSelected() {
        let h = BooksTableHarness(selected: 10)
        #expect(h.table.selectedRow == 0)
        h.apply(books: [BooksTableFixture.books[1]], context: .author(2))
        #expect(h.table.selectedRow == -1)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("deep-link: новый ключ, выбранная книга есть — строка выделена, не пишет")
    func deepLinkSelects() {
        let h = BooksTableHarness(books: [BooksTableFixture.books[0]])
        h.model.selectedBookLibid = 21
        h.model.selectionWrites.removeAll()
        h.apply(books: BooksTableFixture.books, context: .series(1))
        #expect(h.table.selectedRow == 4)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("снятие выделения (selectedRow == -1) не пишет")
    func deselectDoesNotWrite() {
        let h = BooksTableHarness()
        h.select(row: 0)
        h.model.selectionWrites.removeAll()
        h.table.deselectAll(nil)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("тот же ключ и rows.count — reloadData() не вызывается; новый ключ — вызывается")
    func reloadOnlyOnKeyChange() {
        let h = BooksTableHarness()
        let before = h.table.reloadDataCount
        h.model.checkedBookLibids = [10]
        h.model.selectedBookLibid = 11
        h.apply(books: BooksTableFixture.books, context: .author(1))
        #expect(h.table.reloadDataCount == before)
        h.apply(books: BooksTableFixture.books, context: .author(2))
        #expect(h.table.reloadDataCount == before + 1)
    }

    @Test("предложение выбора: мышь на заголовке — текущая; пусто — текущая; книга — книга; из двух — не текущая")
    func proposedSelection() {
        let h = BooksTableHarness()
        let c = h.coordinator
        #expect(c.tableView(h.table, selectionIndexesForProposedSelection: IndexSet(integer: 2)) == IndexSet())
        h.select(row: 1)
        #expect(c.tableView(h.table, selectionIndexesForProposedSelection: IndexSet(integer: 2)) == IndexSet(integer: 1))
        #expect(c.tableView(h.table, selectionIndexesForProposedSelection: IndexSet()) == IndexSet(integer: 1))
        #expect(c.tableView(h.table, selectionIndexesForProposedSelection: IndexSet(integer: 4)) == IndexSet(integer: 4))
        // Из {текущая, другая} берётся не текущая.
        #expect(c.tableView(h.table, selectionIndexesForProposedSelection: IndexSet([1, 3])) == IndexSet(integer: 3))
    }

    @Test("заголовок серии — групповая строка 32pt, книга — 24pt")
    func groupRows() {
        let h = BooksTableHarness()
        #expect(h.coordinator.tableView(h.table, isGroupRow: 2))
        #expect(!h.coordinator.tableView(h.table, isGroupRow: 0))
        #expect(h.coordinator.tableView(h.table, heightOfRow: 2) == 32)
        #expect(h.coordinator.tableView(h.table, heightOfRow: 3) == 24)
        #expect(h.coordinator.tableView(h.table, typeSelectStringFor: nil, row: 2) == nil)
        #expect(h.coordinator.tableView(h.table, typeSelectStringFor: nil, row: 3) == "Гамма")
    }

    @Test("колонки по ширине clip view: сумма = ширине, Жанры и Размер скрываются, Дата видна")
    func layoutColumns() {
        let h = BooksTableHarness()
        func visibleSum() -> CGFloat {
            h.table.tableColumns.filter { !$0.isHidden }.reduce(0) { $0 + $1.width }
        }
        func hidden(_ id: BookTableColumnID) -> Bool {
            h.table.tableColumn(withIdentifier: id.identifier)!.isHidden
        }
        h.coordinator.layoutColumns(width: 1200)
        #expect(visibleSum() == 1200)
        #expect(!hidden(.genres))
        h.coordinator.layoutColumns(width: 600)
        #expect(visibleSum() == 600)
        #expect(hidden(.genres))
        #expect(!hidden(.size))
        h.coordinator.layoutColumns(width: 500)
        #expect(visibleSum() == 500)
        #expect(hidden(.size))
        #expect(!hidden(.date))
    }

    @Test("тексты ячеек: «—» без номера и даты, жанры через запятую, размер файла")
    func cellTexts() {
        let c = BooksTableHarness().coordinator
        let alpha = BooksTableFixture.books[0]
        #expect(c.cellText(for: alpha, column: .num) == "—")
        #expect(c.cellText(for: alpha, column: .date) == "—")
        #expect(c.cellText(for: alpha, column: .genres) == "Фантастика, Детектив")
        #expect(c.cellText(for: alpha, column: .size)
                == ByteCountFormatter.string(fromByteCount: 2048, countStyle: .file))
        #expect(c.cellText(for: BooksTableFixture.books[2], column: .num) == "1")
    }

    @Test("ячейка названия: галочка, жирность выбранной, метка доступности")
    func titleCellState() {
        let h = BooksTableHarness(selected: 10, checked: [11])
        #expect(h.titleCell(row: 0)?.showsSelected == true)
        #expect(h.titleCell(row: 1)?.showsSelected == false)
        #expect(h.titleCell(row: 1)?.checkbox.isOn == true)
        #expect(h.titleCell(row: 0)?.checkbox.accessibilityLabel() == "Отметить: Альфа")
        #expect(h.titleCell(row: 3)?.leadingInset == 30)
    }

    @Test("переключение галочки через координатор не пишет selectedBookLibid")
    func toggleDoesNotSelect() {
        let h = BooksTableHarness()
        #expect(h.titleCell(row: 1)?.checkbox.accessibilityPerformPress() == true)
        #expect(h.model.checkedBookLibids == [11])
        h.coordinator.toggleCheck(libid: 11)
        #expect(h.model.checkedBookLibids.isEmpty)
        #expect(h.model.selectionWrites.isEmpty)
        #expect(h.table.selectedRow == -1)
    }

    @Test("клик по галочке не выделяет строку: таблица отдаёт событие галочке")
    func checkboxGetsMouse() {
        let h = BooksTableHarness()
        let box = BookCheckbox()
        #expect(h.table.validateProposedFirstResponder(box, for: nil))
    }
}
