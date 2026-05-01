import SwiftUI
import AppKit

/// `NSTableView`-backed lazy list, used in place of SwiftUI `Table` when the
/// item count is large (100k+). SwiftUI Table on macOS 26 spends ~20 seconds
/// diffing transitions like 166k → 500; `NSTableView.reloadData()` is O(1)
/// at the API level and lazily fetches rows for the visible viewport via
/// the data-source protocol — millions of rows are routine for it.
///
/// Single-column, no header. Selection is single, bound externally.
/// `trailingLabelFor` is optional — when set, each row renders a secondary
/// right-aligned text (used for per-row book counts in author/series lists).
struct LazyListTable<Item: Identifiable>: NSViewRepresentable where Item.ID: Hashable {
    let items: [Item]
    @Binding var selectedID: Item.ID?
    /// Pure label producer. Called per visible row, so it must be cheap.
    let labelFor: (Item) -> String
    /// Optional right-aligned secondary label (e.g. count).
    var trailingLabelFor: ((Item) -> String)? = nil

    private static var cellIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("LazyListTable.cell")
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.headerView = nil
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 1)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
        column.resizingMask = .autoresizingMask
        column.minWidth = 100
        tableView.addTableColumn(column)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.action = #selector(Coordinator.handleClick(_:))

        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let tableView = scrollView.documentView as! NSTableView
        let coordinator = context.coordinator

        coordinator.labelFor = labelFor
        coordinator.trailingLabelFor = trailingLabelFor
        coordinator.binding = $selectedID

        // Cheap structural-change check: count + first/last IDs is enough to
        // tell apart the transitions we care about (166k → 500 → 40 etc).
        // A full deep equality check would cost more than just reloading.
        let newCount = items.count
        let firstID = items.first?.id
        let lastID = items.last?.id
        let dataChanged = coordinator.itemCount != newCount
            || coordinator.firstID != firstID
            || coordinator.lastID != lastID
        coordinator.items = items
        coordinator.itemCount = newCount
        coordinator.firstID = firstID
        coordinator.lastID = lastID
        if dataChanged {
            tableView.reloadData()
        }

        // Sync selection from the SwiftUI binding into the NSTableView.
        if let id = selectedID, let row = items.firstIndex(where: { $0.id == id }) {
            if tableView.selectedRow != row {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        } else if tableView.selectedRow != -1 {
            tableView.deselectAll(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, labelFor: labelFor,
                    trailingLabelFor: trailingLabelFor, binding: $selectedID)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var items: [Item]
        var itemCount: Int
        var firstID: Item.ID?
        var lastID: Item.ID?
        var labelFor: (Item) -> String
        var trailingLabelFor: ((Item) -> String)?
        var binding: Binding<Item.ID?>

        init(items: [Item], labelFor: @escaping (Item) -> String,
             trailingLabelFor: ((Item) -> String)?,
             binding: Binding<Item.ID?>) {
            self.items = items
            self.itemCount = items.count
            self.firstID = items.first?.id
            self.lastID = items.last?.id
            self.labelFor = labelFor
            self.trailingLabelFor = trailingLabelFor
            self.binding = binding
        }

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView,
                       viewFor tableColumn: NSTableColumn?,
                       row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("LazyListTable.cell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? TwoLabelCell)
                ?? makeCell(identifier: id)
            if row >= 0 && row < items.count {
                let item = items[row]
                cell.mainLabel.stringValue = labelFor(item)
                if let trailing = trailingLabelFor?(item), !trailing.isEmpty {
                    cell.trailingLabel.stringValue = trailing
                    cell.trailingLabel.isHidden = false
                } else {
                    cell.trailingLabel.stringValue = ""
                    cell.trailingLabel.isHidden = true
                }
            }
            return cell
        }

        private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> TwoLabelCell {
            let cell = TwoLabelCell()
            cell.identifier = identifier
            return cell
        }

        @objc func handleClick(_ sender: NSTableView) {
            let row = sender.selectedRow
            if row >= 0 && row < items.count {
                binding.wrappedValue = items[row].id
            } else {
                binding.wrappedValue = nil
            }
        }
    }

    /// Two-label row cell: left main label (truncating tail) + right trailing
    /// secondary label (smaller font, secondary color). Trailing label hides
    /// itself when empty, so single-label clients see no visual difference.
    final class TwoLabelCell: NSView {
        let mainLabel: NSTextField = {
            let f = NSTextField(labelWithString: "")
            f.isBordered = false
            f.drawsBackground = false
            f.isEditable = false
            f.isSelectable = false
            f.lineBreakMode = .byTruncatingTail
            f.cell?.usesSingleLineMode = true
            return f
        }()
        let trailingLabel: NSTextField = {
            let f = NSTextField(labelWithString: "")
            f.isBordered = false
            f.drawsBackground = false
            f.isEditable = false
            f.isSelectable = false
            f.alignment = .right
            f.font = NSFont.systemFont(ofSize: 11)
            f.textColor = .secondaryLabelColor
            return f
        }()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setupSubviews()
        }
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupSubviews()
        }

        private func setupSubviews() {
            mainLabel.translatesAutoresizingMaskIntoConstraints = false
            trailingLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(mainLabel)
            addSubview(trailingLabel)

            // Trailing must keep its intrinsic width; main shrinks first.
            trailingLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            trailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            mainLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            NSLayoutConstraint.activate([
                mainLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                mainLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                mainLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingLabel.leadingAnchor, constant: -8),

                trailingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                trailingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }
}
