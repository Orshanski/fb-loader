import SwiftUI
import AppKit

/// Протокол, а не AppState: тесты подставляют подделку и считают записи выбора.
@MainActor
protocol BooksTableModel: AnyObject {
    var selectedBookLibid: Int32? { get set }
    var checkedBookLibids: Set<Int32> { get set }
    var dateFilter: DateRangeFilter? { get }
    func applyDateFilter(_ next: DateRangeFilter?)
}

extension AppState: BooksTableModel {}

struct BooksTableRepresentable: NSViewRepresentable {
    let state: AppState
    let library: Library
    let rows: BookTableRows
    let key: BooksTableKey
    let exportAction: ExportAction

    func makeCoordinator() -> Coordinator {
        Coordinator(model: state, library: library, exportAction: exportAction)
    }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(coordinator: context.coordinator)
    }

    func updateNSView(_: NSScrollView, context: Context) {
        let c = context.coordinator
        c.model = state
        c.library = library
        c.exportAction = exportAction
        // Выбор и галочки читаются здесь, а не в body: их смена перезапускает
        // только updateNSView, выборка не пересчитывается.
        c.apply(rows: rows, key: key,
                selectedLibid: state.selectedBookLibid, checked: state.checkedBookLibids)
    }

    static func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let table = BooksNSTableView()
        table.style = .plain
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnResizing = false
        table.allowsColumnReordering = false
        table.allowsColumnSelection = false
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.usesAutomaticRowHeights = false
        table.floatsGroupRows = false
        table.gridStyleMask = []
        table.selectionHighlightStyle = .regular
        table.intercellSpacing = .zero
        table.rowHeight = BooksNSTableView.bookRowHeight
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        for id in BookTableColumnID.allCases {
            let column = NSTableColumn(identifier: id.identifier)
            column.title = id.headerTitle
            column.headerCell = BooksHeaderCell(column: id)
            column.resizingMask = []
            column.minWidth = 0
            column.maxWidth = .greatestFiniteMagnitude
            column.isEditable = false
            table.addTableColumn(column)
        }

        let header = BooksHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: BooksHeaderView.height))
        header.releasedOverDate = { [weak coordinator] in coordinator?.completePendingDatePress() }
        table.headerView = header
        table.cornerView = nil

        let scrollView = BooksScrollView()
        scrollView.onTile = { [weak coordinator] width in coordinator?.layoutColumns(width: width) }
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 4, right: 0)
        scrollView.documentView = table

        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.attach(table: table, scrollView: scrollView)
        return scrollView
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSPopoverDelegate {
        var model: any BooksTableModel
        var library: Library
        var exportAction: ExportAction
        private(set) var rows = BookTableRows.empty
        private(set) var key: BooksTableKey?
        private(set) weak var tableView: BooksNSTableView?
        private var selectedLibid: Int32?
        private var checked: Set<Int32> = []
        /// Выделение меняет код, а не пользователь — в модель не пишем.
        private var isUpdatingSelection = false
        private var datePopover: NSPopover?
        private var lastPopoverCloseTimestamp: TimeInterval?
        private(set) var pendingDatePress: DatePress?

        init(model: any BooksTableModel, library: Library, exportAction: ExportAction) {
            self.model = model
            self.library = library
            self.exportAction = exportAction
        }

        func attach(table: BooksNSTableView, scrollView: NSScrollView) {
            tableView = table
            let clip = scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(clipBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification, object: clip)
            table.onSpaceToggle = { [weak self] in self?.toggleCheckAtSelectedRow() }
            table.menuProvider = { [weak self] row in self?.contextMenu(forRow: row) }
            layoutColumns(width: clip.frame.width)
        }

        /// От ширины clip view, а не панели: с постоянной полосой прокрутки
        /// колонки уже панели на её ширину. Пишет только изменившееся.
        func layoutColumns(width: CGFloat) {
            // До первой раскладки SwiftUI ширина clip view нулевая.
            guard let tableView, width > 0 else { return }
            let layout = BookTableColumns.columnLayout(forWidth: width)
            for id in BookTableColumnID.allCases {
                guard let column = tableView.tableColumn(withIdentifier: id.identifier) else { continue }
                if let w = layout.width(of: id) {
                    if column.isHidden { column.isHidden = false }
                    if column.width != w { column.width = w }
                } else if !column.isHidden {
                    column.isHidden = true
                }
            }
        }

        func apply(rows newRows: BookTableRows, key newKey: BooksTableKey,
                   selectedLibid newSelected: Int32?, checked newChecked: Set<Int32>) {
            guard let tableView else { return }
            let structural = newKey != key || newRows.count != rows.count
            let cellsChanged = newSelected != selectedLibid || newChecked != checked
            rows = newRows
            key = newKey
            selectedLibid = newSelected
            checked = newChecked
            if structural {
                withoutWritingSelection { tableView.reloadData() }
                syncSelection(of: tableView, to: newSelected)
                scroll(tableView, to: newRows.scrollTarget(selectedLibid: newSelected))
                if let header = tableView.headerView as? BooksHeaderView { header.dateState = dateHeaderState }
                tableView.headerView?.needsDisplay = true
                tableView.updateHoverFromMouse()
            } else {
                syncSelection(of: tableView, to: newSelected)
                if cellsChanged { reloadLiveTitleCells(of: tableView) }
            }
        }

        /// Все живые строки, а не только `visibleRect`: AppKit держит строки за краем окна, и они иначе остались бы со старым видом.
        private func reloadLiveTitleCells(of tableView: NSTableView) {
            guard let column = tableView.tableColumns.firstIndex(where: {
                $0.identifier == BookTableColumnID.title.identifier })
            else { return }
            var live = IndexSet()
            tableView.enumerateAvailableRowViews { _, row in live.insert(row) }
            guard !live.isEmpty else { return }
            withoutWritingSelection {
                tableView.reloadData(forRowIndexes: live, columnIndexes: IndexSet(integer: column))
            }
        }

        private func scroll(_ tableView: NSTableView, to target: BookTableRows.ScrollTarget) {
            switch target {
            case .top:
                if tableView.numberOfRows > 0 { tableView.scrollRowToVisible(0) }
            case .row(let row, let header):
                if let header { tableView.scrollRowToVisible(header) }
                tableView.scrollRowToVisible(row)
            }
        }

        func withoutWritingSelection(_ body: () -> Void) {
            isUpdatingSelection = true
            defer { isUpdatingSelection = false }
            body()
        }

        func syncSelection(of tableView: NSTableView, to libid: Int32?) {
            withoutWritingSelection {
                if let libid, let row = rows.row(ofLibid: libid) {
                    if tableView.selectedRow != row {
                        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    }
                } else if tableView.selectedRow != -1 {
                    tableView.deselectAll(nil)
                }
            }
        }

        func toggleCheck(libid: Int32) {
            if model.checkedBookLibids.contains(libid) {
                model.checkedBookLibids.remove(libid)
            } else {
                model.checkedBookLibids.insert(libid)
            }
        }

        func cellText(for book: Book, column: BookTableColumnID) -> String {
            switch column {
            case .title: book.title
            case .num: book.seriesNum.map { "\($0)" } ?? "—"
            case .size: ByteCountFormatter.string(fromByteCount: Int64(book.size), countStyle: .file)
            case .date: book.dateAdded.map(DateFormat.dayMonthYear.string(from:)) ?? "—"
            case .genres: book.genreIDs.compactMap { library.genreByID[$0]?.name }.joined(separator: ", ")
            }
        }

        @objc private func clipBoundsDidChange(_: Notification) {
            tableView?.updateHoverFromMouse()
        }

        func toggleCheckAtSelectedRow() {
            guard let tableView, let libid = rows.libid(at: tableView.selectedRow) else { return }
            toggleCheck(libid: libid)
        }

        /// Выгружаются книги с галочками, а не строка под курсором.
        func contextMenu(forRow row: Int) -> NSMenu? {
            guard rows.isBook(row) else { return nil }
            let count = model.checkedBookLibids.count
            let menu = NSMenu()
            menu.autoenablesItems = false
            let item = NSMenuItem(title: "Выгрузить отмеченные (\(count))",
                                  action: #selector(exportChecked(_:)), keyEquivalent: "")
            item.target = self
            item.isEnabled = count > 0
            menu.addItem(item)
            return menu
        }

        @objc func exportChecked(_: Any?) { exportAction.perform() }

        func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
            (rowView as? BooksRowView)?.isHovered = row == (tableView as? BooksNSTableView)?.hoveredRow
        }

        var dateHeaderState: DateHeaderState {
            guard let key, key.context != nil else { return .disabled }
            return key.dates == nil ? .normal : .active
        }

        var isDatePopoverShown: Bool { datePopover?.isShown == true }

        func datePress(at timestamp: TimeInterval) -> DatePress {
            if isDatePopoverShown || lastPopoverCloseTimestamp == timestamp { return .close }
            return dateHeaderState == .disabled ? .ignore : .open
        }

        func perform(_ action: DatePress) {
            switch action {
            case .ignore: break
            case .close: datePopover?.performClose(nil)
            case .open: showDatePopover()
            }
        }

        func notePopoverClosed(at timestamp: TimeInterval?) {
            lastPopoverCloseTimestamp = timestamp
        }

        private func showDatePopover() {
            guard dateHeaderState != .disabled, !isDatePopoverShown,
                  let tableView, let header = tableView.headerView,
                  let column = tableView.tableColumns.firstIndex(where: {
                      $0.identifier == BookTableColumnID.date.identifier })
            else { return }
            let popover = NSPopover()
            popover.behavior = .transient
            popover.delegate = self
            let host = NSHostingController(rootView: DateFilterPopover(current: model.dateFilter) { [weak self] next in
                self?.model.applyDateFilter(next)
                self?.datePopover?.performClose(nil)
            })
            host.sizingOptions = [.preferredContentSize]
            popover.contentViewController = host
            datePopover = popover
            // Шапка flipped: .maxY — её нижний край, поповер под заголовком.
            let anchor = BooksHeaderCell.contentRect(for: .date, in: header.headerRect(ofColumn: column))
            popover.show(relativeTo: anchor, of: header, preferredEdge: .maxY)
        }

        func popoverWillClose(_: Notification) {
            notePopoverClosed(at: NSApp.currentEvent?.timestamp)
        }

        func popoverDidClose(_: Notification) {
            datePopover = nil
        }

        /// Решение принимается на нажатии: transient-поповер закрывается тем же mouseDown раньше, чем отпускание дойдёт до didClick.
        func tableView(_: NSTableView, mouseDownInHeaderOf tableColumn: NSTableColumn) {
            headerMouseDown(on: BookTableColumnID(rawValue: tableColumn.identifier.rawValue),
                            at: NSApp.currentEvent?.timestamp ?? -1)
        }

        func headerMouseDown(on column: BookTableColumnID?, at timestamp: TimeInterval) {
            pendingDatePress = column == .date ? datePress(at: timestamp) : nil
        }

        func tableView(_: NSTableView, didClick tableColumn: NSTableColumn) {
            guard tableColumn.identifier == BookTableColumnID.date.identifier else { return }
            // Нет нажатия мышью — это штатное нажатие VoiceOver на ячейку.
            if pendingDatePress == nil { pendingDatePress = datePress(at: NSApp.currentEvent?.timestamp ?? -1) }
            completePendingDatePress()
        }

        func completePendingDatePress() {
            guard let action = pendingDatePress else { return }
            pendingDatePress = nil
            perform(action)
        }

        // MARK: Data source / delegate

        func numberOfRows(in _: NSTableView) -> Int { rows.count }

        func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
            rows.rows.indices.contains(row) && !rows.isBook(row)
        }

        func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
            rows.isBook(row) ? BooksNSTableView.bookRowHeight : BooksNSTableView.seriesHeaderHeight
        }

        func tableView(_ tableView: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("BooksTable.row")
            if let view = tableView.makeView(withIdentifier: id, owner: nil) as? BooksRowView { return view }
            let view = BooksRowView()
            view.identifier = id
            return view
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.rows.indices.contains(row) else { return nil }
            switch rows.rows[row] {
            case .seriesHeader(let series, let count):
                let id = NSUserInterfaceItemIdentifier("BooksTable.series")
                let cell = tableView.makeView(withIdentifier: id, owner: nil) as? SeriesHeaderCellView
                    ?? { let c = SeriesHeaderCellView(); c.identifier = id; return c }()
                cell.configure(series: series, count: count)
                return cell
            case .book(let book, let inSeries):
                guard let tableColumn,
                      let column = BookTableColumnID(rawValue: tableColumn.identifier.rawValue)
                else { return nil }
                if column == .title {
                    let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? BookTitleCellView
                        ?? { let c = BookTitleCellView(); c.identifier = column.identifier; return c }()
                    let libid = book.libid
                    cell.configure(book: book, inSeries: inSeries,
                                   isChecked: checked.contains(libid),
                                   isSelected: selectedLibid == libid,
                                   onToggle: { [weak self] in self?.toggleCheck(libid: libid) })
                    return cell
                }
                let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? BookTextCellView
                    ?? BookTextCellView(column: column)
                cell.configure(text: cellText(for: book, column: column))
                return cell
            }
        }

        func tableView(_: NSTableView, typeSelectStringFor _: NSTableColumn?, row: Int) -> String? {
            rows.book(at: row)?.title
        }

        func tableView(_ tableView: NSTableView,
                       selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
            let current = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
            // ⇧-стрелка может предложить {текущая, следующая}: берём не текущую.
            let candidate = proposed.first(where: { $0 != current }) ?? proposed.first
            let byKeyboard = (tableView as? BooksNSTableView)?.isHandlingKeyDown ?? false
            guard let row = rows.resolveSelection(proposed: candidate, current: current,
                                                  byKeyboard: byKeyboard)
            else { return IndexSet() }
            return IndexSet(integer: row)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection,
                  let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            guard let libid = rows.libid(at: row) else { return }
            model.selectedBookLibid = libid
            // Мышью заголовок не подтягиваем: таблица под курсором не должна сдвигаться.
            let byKeyboard = (tableView as? BooksNSTableView)?.isHandlingKeyDown ?? false
            if byKeyboard, row > 0, !rows.isBook(row - 1) { tableView.scrollRowToVisible(row - 1) }
        }
    }
}
