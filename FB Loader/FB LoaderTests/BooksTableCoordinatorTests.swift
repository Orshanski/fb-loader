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

    @Test("клик по галочке переключает её и не меняет выбор")
    func checkboxClickKeepsSelection() {
        let h = BooksTableHarness()
        h.select(row: 0)
        h.model.selectionWrites.removeAll()
        h.window.layoutIfNeeded()
        h.table.layoutSubtreeIfNeeded()
        let cell = h.table.view(atColumn: 0, row: 1, makeIfNecessary: true) as! BookTitleCellView
        cell.layoutSubtreeIfNeeded()
        let box = cell.checkbox
        let point = box.convert(NSPoint(x: box.bounds.midX, y: box.bounds.midY), to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: h.window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let hit = h.window.contentView?.superview?.hitTest(point)
        // Мышь достаётся галочке, а не таблице: NSTableView.mouseDown, который выделяет строку, не вызывается.
        #expect(hit === box)
        hit?.mouseDown(with: event(.leftMouseDown))
        hit?.mouseUp(with: event(.leftMouseUp))
        #expect(h.model.checkedBookLibids == [11])
        #expect(h.table.selectedRow == 0)
        #expect(h.model.selectionWrites.isEmpty)
    }
}

@MainActor
private func keyEvent(_ characters: String, keyCode: UInt16,
                      modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                     windowNumber: 0, context: nil, characters: characters,
                     charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
}

@MainActor
private func arrow(_ scalar: Int, keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    keyEvent(String(Character(UnicodeScalar(UInt32(scalar))!)), keyCode: keyCode,
             modifiers: modifiers.union([.numericPad, .function]))
}

@MainActor private func down(_ m: NSEvent.ModifierFlags = []) -> NSEvent { arrow(NSDownArrowFunctionKey, keyCode: 125, m) }
@MainActor private func up(_ m: NSEvent.ModifierFlags = []) -> NSEvent { arrow(NSUpArrowFunctionKey, keyCode: 126, m) }
@MainActor private func space() -> NSEvent { keyEvent(" ", keyCode: 49) }

@Suite("BooksTable keyboard and menu")
@MainActor
struct BooksTableKeyboardTests {
    @Test("↓ и ⇧↓: выбор перескакивает заголовок серии и пишется в модель")
    func arrowsSkipHeader() {
        for mods: NSEvent.ModifierFlags in [[], [.shift]] {
            let h = BooksTableHarness()
            h.select(row: 1)
            h.model.selectionWrites.removeAll()
            h.table.keyDown(with: down(mods))
            #expect(h.table.selectedRow == 3, "mods \(mods.rawValue)")
            #expect(h.model.selectionWrites == [20], "mods \(mods.rawValue)")
        }
    }

    @Test("⌥↓ штатно прыгает в конец: выбрана последняя книга, не заголовок")
    func optionDownJumpsToEnd() {
        let h = BooksTableHarness()
        h.select(row: 1)
        h.model.selectionWrites.removeAll()
        h.table.keyDown(with: down([.option]))
        #expect(h.table.selectedRow == 4)
        #expect(h.model.selectionWrites == [21])
    }

    @Test("⌥↑ штатно прыгает в начало: с заголовком в строке 0 выбрана первая книга")
    func optionUpJumpsToStart() {
        let h = BooksTableHarness(books: Array(BooksTableFixture.books[2...]))
        h.select(row: 2)
        h.model.selectionWrites.removeAll()
        h.table.keyDown(with: up([.option]))
        #expect(h.table.selectedRow == 1)
        #expect(h.model.selectionWrites == [20])
    }

    @Test("⌘↓ и ⌘↑ штатно шагают на одну строку: заголовок серии не выбирается")
    func commandArrowsSkipHeader() {
        let h = BooksTableHarness()
        h.select(row: 1)
        h.table.keyDown(with: down([.command]))
        #expect(h.table.selectedRow == 3)
        h.table.keyDown(with: up([.command]))
        #expect(h.table.selectedRow == 1)
    }

    @Test("без выбора ↑ — последняя книга")
    func upWithoutSelection() {
        let h = BooksTableHarness()
        h.table.keyDown(with: up())
        #expect(h.table.selectedRow == 4)
        #expect(h.model.selectionWrites == [21])
    }

    @Test("на последней книге ↓ — выбор на месте")
    func downAtEnd() {
        let h = BooksTableHarness()
        h.select(row: 4)
        h.model.selectionWrites.removeAll()
        h.table.keyDown(with: down())
        #expect(h.table.selectedRow == 4)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("без выбора ↓ при заголовке в строке 0 — первая книга; ↑ на ней — на месте")
    func headerAtTop() {
        let series = Array(BooksTableFixture.books[2...])
        let h = BooksTableHarness(books: series)
        h.table.keyDown(with: down())
        #expect(h.table.selectedRow == 1)
        h.table.keyDown(with: up())
        #expect(h.table.selectedRow == 1)
    }

    @Test("пробел с выделением переключает галочку туда и обратно, выбор не меняется")
    func spaceToggles() {
        let h = BooksTableHarness()
        h.select(row: 0)
        h.model.selectionWrites.removeAll()
        h.table.keyDown(with: space())
        #expect(h.model.checkedBookLibids == [10])
        h.table.keyDown(with: space())
        #expect(h.model.checkedBookLibids.isEmpty)
        #expect(h.table.selectedRow == 0)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("пробел без выделения — ничего; выбранной в модели книги нет в строках — ничего")
    func spaceWithoutSelection() {
        let h = BooksTableHarness()
        h.table.keyDown(with: space())
        #expect(h.model.checkedBookLibids.isEmpty)
        let hidden = BooksTableHarness(selected: 99)
        hidden.table.keyDown(with: space())
        #expect(hidden.model.checkedBookLibids.isEmpty)
    }

    @Test("пробел меньше чем через секунду после буквы уходит в type-select")
    func spaceAfterLetter() {
        let h = BooksTableHarness()
        h.select(row: 0)
        var clock = Date(timeIntervalSinceReferenceDate: 1000)
        h.table.now = { clock }
        h.table.keyDown(with: keyEvent("б", keyCode: 43))
        #expect(h.table.lastTypeSelectKey == clock)
        clock += 0.5
        h.table.keyDown(with: space())
        #expect(h.model.checkedBookLibids.isEmpty)
    }

    @Test("меню на книге: один пункт с N, неактивен при N = 0, действие — ExportAction")
    func contextMenu() {
        let h = BooksTableHarness(checked: [10, 20])
        var exports = 0
        h.exportAction.perform = { exports += 1 }
        let menu = h.coordinator.contextMenu(forRow: 0)
        #expect(menu?.items.count == 1)
        #expect(menu?.items.first?.title == "Выгрузить отмеченные (2)")
        #expect(menu?.items.first?.isEnabled == true)
        menu?.performActionForItem(at: 0)
        #expect(exports == 1)

        h.model.checkedBookLibids = []
        let empty = h.coordinator.contextMenu(forRow: 3)
        #expect(empty?.items.first?.title == "Выгрузить отмеченные (0)")
        #expect(empty?.items.first?.isEnabled == false)
    }

    @Test("меню на заголовке серии и пустом месте — nil")
    func noMenuOnHeader() {
        let h = BooksTableHarness()
        #expect(h.coordinator.contextMenu(forRow: 2) == nil)
        #expect(h.coordinator.contextMenu(forRow: -1) == nil)
    }

    @Test("ПКМ по невыделенной книге: меню есть, выбор и модель не меняются")
    func rightClickKeepsSelection() {
        let h = BooksTableHarness()
        h.select(row: 0)
        h.model.selectionWrites.removeAll()
        let rect = h.table.rect(ofRow: 3)
        let point = h.table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [],
                                       timestamp: 0, windowNumber: h.window.windowNumber, context: nil,
                                       eventNumber: 0, clickCount: 1, pressure: 1)!
        #expect(h.table.menu(for: event) != nil)
        #expect(h.table.selectedRow == 0)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("hover сбрасывается при перезагрузке строк")
    func hoverResetsOnReload() {
        let h = BooksTableHarness()
        h.table.setHoveredRow(1)
        #expect(h.table.hoveredRow == 1)
        // reloadData напрямую: apply ещё пересчитывает hover по реальному курсору — тест зависел бы от мыши.
        h.table.reloadData()
        #expect(h.table.hoveredRow == -1)
    }
}

@Suite("BooksTable header")
@MainActor
struct BooksTableHeaderTests {
    private let dates = DateRangeFilter(from: Date(timeIntervalSinceReferenceDate: 0),
                                        to: Date(timeIntervalSinceReferenceDate: 86_400))

    @Test("шапка 33pt, без cornerView, у каждой колонки своя ячейка шапки")
    func headerSetup() {
        let h = BooksTableHarness()
        #expect(h.table.headerView is BooksHeaderView)
        #expect(h.table.headerView?.frame.height == 33)
        #expect(h.table.cornerView == nil)
        for column in h.table.tableColumns {
            #expect((column.headerCell as? BooksHeaderCell)?.column.identifier == column.identifier)
        }
    }

    @Test("состояние «Даты»: без контекста — неактивна, без фильтра — обычная, с фильтром — акцент")
    func dateState() {
        let h = BooksTableHarness(context: nil)
        let header = h.table.headerView as? BooksHeaderView
        #expect(header?.dateState == .disabled)
        h.apply(books: BooksTableFixture.books, context: .author(1))
        #expect(header?.dateState == .normal)
        h.apply(books: BooksTableFixture.books, context: .author(1), dates: dates)
        #expect(header?.dateState == .active)
    }

    @Test("нажатие на «Дату»: без контекста — игнор, с контекстом — открыть")
    func datePressByContext() {
        #expect(BooksTableHarness(context: nil).coordinator.datePress(at: 1) == .ignore)
        #expect(BooksTableHarness().coordinator.datePress(at: 1) == .open)
    }

    @Test("клик, закрывший transient-поповер, поповер заново не открывает")
    func pressThatClosedPopover() {
        let c = BooksTableHarness().coordinator
        c.notePopoverClosed(at: 42)
        #expect(c.datePress(at: 42) == .close)
        #expect(c.datePress(at: 43) == .open)
    }

    @Test("«Дата»: решение берётся на mouseDown, отпускание его выполняет и сбрасывает")
    func headerPressFlow() {
        let h = BooksTableHarness()
        let c = h.coordinator
        let dateColumn = h.table.tableColumn(withIdentifier: BookTableColumnID.date.identifier)!
        c.headerMouseDown(on: .date, at: 1)
        #expect(c.pendingDatePress == .open)
        c.headerMouseDown(on: .num, at: 2)
        #expect(c.pendingDatePress == nil)
        c.notePopoverClosed(at: 42)
        c.headerMouseDown(on: .date, at: 42)
        #expect(c.pendingDatePress == .close)
        c.tableView(h.table, didClick: dateColumn)
        #expect(c.pendingDatePress == nil)
        #expect(!c.isDatePopoverShown)
    }

    @Test("«Дата» без контекста: нажатие игнорируется, поповер не открывается")
    func headerPressWithoutContext() {
        let h = BooksTableHarness(context: nil)
        let dateColumn = h.table.tableColumn(withIdentifier: BookTableColumnID.date.identifier)!
        h.coordinator.headerMouseDown(on: .date, at: 1)
        #expect(h.coordinator.pendingDatePress == .ignore)
        h.coordinator.tableView(h.table, didClick: dateColumn)
        #expect(!h.coordinator.isDatePopoverShown)
    }

    @Test("области подписей: Название с 54pt, Дата 100pt после промежутка, шеврон в 16pt от края последней колонки")
    func contentRects() {
        let frame = NSRect(x: 0, y: 0, width: 500, height: 33)
        #expect(BooksHeaderCell.contentRect(for: .title, in: frame).minX == 54)
        let date = NSRect(x: 600, y: 0, width: 126, height: 33)
        let dateContent = BooksHeaderCell.contentRect(for: .date, in: date)
        #expect(dateContent.minX == 610)
        #expect(dateContent.width == 100)
        #expect(date.maxX - dateContent.maxX == 16)
        let genres = BooksHeaderCell.contentRect(for: .genres, in: NSRect(x: 800, y: 0, width: 246, height: 33))
        #expect(genres.minX == 810)
        #expect(genres.width == 220)
    }
}


@Suite("BooksTable scrolling and live rows")
@MainActor
struct BooksTableScrollTests {
    /// 40 книг без серии (libid 1…40), затем [Серия] (строка 40) и 30 книг серии (libid 101…130, строки 41…70).
    private func manyBooks() -> [Book] {
        (1...40).map { BooksTableFixture.book(Int32($0), "Л\($0)") }
            + (1...30).map { BooksTableFixture.book(Int32(100 + $0), "С\($0)", series: 1, num: Int16($0)) }
    }

    /// Верх списка — отрицательный origin: под шапкой таблицы.
    private let topY = -BooksHeaderView.height

    private var clipY: (BooksTableHarness) -> CGFloat { { $0.scrollView.contentView.bounds.origin.y } }

    private func scrollToRow(_ h: BooksTableHarness, _ row: Int) {
        h.table.scrollRowToVisible(row)
        h.scrollView.reflectScrolledClipView(h.scrollView.contentView)
    }

    @Test("смена ключа без выбранной книги — к началу")
    func newKeyScrollsToTop() {
        let h = BooksTableHarness(books: manyBooks())
        scrollToRow(h, 70)
        #expect(clipY(h) > topY)
        h.apply(books: manyBooks(), context: .author(2))
        #expect(clipY(h) == topY)
    }

    @Test("deep-link: новая выборка с выбранной книгой — книга и заголовок её серии видимы")
    func deepLinkScrollsToBookWithHeader() {
        let h = BooksTableHarness(books: manyBooks())
        scrollToRow(h, 70)
        h.model.selectedBookLibid = 101
        h.apply(books: manyBooks(), context: .author(2))
        let visible = h.table.rows(in: h.table.visibleRect)
        #expect(NSLocationInRange(40, visible))
        #expect(NSLocationInRange(41, visible))
    }

    @Test("выбор мышью первой книги серии не двигает таблицу, стрелка ↑ подтягивает заголовок")
    func headerScrollOnlyByKeyboard() {
        let books = (1...60).map { BooksTableFixture.book(Int32($0), "С\($0)", series: 1, num: Int16($0)) }
        let h = BooksTableHarness(books: books)
        let headerHeight = BooksNSTableView.seriesHeaderHeight
        func scrollPastHeader() {
            h.scrollView.contentView.scroll(to: NSPoint(x: 0, y: topY + headerHeight))
            h.scrollView.reflectScrolledClipView(h.scrollView.contentView)
        }
        scrollPastHeader()
        h.select(row: 1)
        #expect(clipY(h) == topY + headerHeight)

        h.select(row: 2)
        scrollPastHeader()
        h.table.keyDown(with: {
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     characters: String(Character(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)),
                                     charactersIgnoringModifiers: String(Character(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)),
                                     isARepeat: false, keyCode: 126)!
            return e
        }())
        #expect(h.table.selectedRow == 1)
        #expect(clipY(h) == topY)
    }

    @Test("смена галочек обновляет и живые строки за краем окна")
    func liveRowsOutsideVisibleRectUpdate() {
        let h = BooksTableHarness(books: manyBooks())
        h.window.setContentSize(NSSize(width: 900, height: 120))
        h.table.layoutSubtreeIfNeeded()
        scrollToRow(h, 35)
        scrollToRow(h, 5)
        h.model.checkedBookLibids = Set(manyBooks().map(\.libid))
        h.model.selectedBookLibid = 7
        h.apply(books: manyBooks(), context: .author(1))
        var outside = 0
        h.table.enumerateAvailableRowViews { rowView, row in
            guard let libid = h.coordinator.rows.libid(at: row),
                  let cell = h.table.view(atColumn: 0, row: row, makeIfNecessary: false) as? BookTitleCellView
            else { return }
            if !rowView.frame.intersects(h.table.visibleRect) { outside += 1 }
            #expect(cell.checkbox.isOn, "row \(row)")
            #expect(cell.showsSelected == (libid == 7), "row \(row)")
        }
        #expect(outside > 0)
    }
}
