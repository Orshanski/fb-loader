import AppKit
import SwiftUI
import Testing
@testable import FB_Loader

@Suite("LazyListTable")
@MainActor
struct LazyListTableTests {
    private struct Item: Identifiable { let id: Int }

    private final class Box { var writes: [Int?] = [] }

    /// `delegate` у таблицы слабый — координатор держит вызывающий тест.
    private func makeTable(items: [Int]) -> (NSTableView, LazyListTable<Item>.Coordinator, Box) {
        let box = Box()
        let binding = Binding<Int?>(get: { box.writes.last ?? nil },
                                    set: { box.writes.append($0) })
        let coordinator = LazyListTable<Item>.Coordinator(
            items: items.map(Item.init), labelFor: { "\($0.id)" },
            trailingLabelFor: nil, rowStyleFor: { _ in SidebarRowStyle() },
            binding: binding)
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: .init("col")))
        table.dataSource = coordinator
        table.delegate = coordinator
        table.reloadData()
        return (table, coordinator, box)
    }

    @Test("смена выделенной строки пользователем (стрелки, клик) пишет выбор")
    func userSelectionChangeWritesBinding() {
        let (table, coordinator, box) = makeTable(items: [10, 20, 30])

        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        #expect(box.writes == [10, 20])
        withExtendedLifetime(coordinator) {}
    }

    @Test("снятие выделения пишет nil")
    func deselectWritesNil() {
        let (table, coordinator, box) = makeTable(items: [10, 20])
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        table.deselectAll(nil)

        #expect(box.writes == [10, nil])
        withExtendedLifetime(coordinator) {}
    }

    @Test("синхронизация выделения из модели выбор обратно не пишет")
    func programmaticSyncDoesNotWrite() {
        let (table, coordinator, box) = makeTable(items: [10, 20])

        coordinator.syncSelection(of: table, to: 20)
        #expect(table.selectedRow == 1)
        // Выбранного нет среди строк (скрыт фильтром) — выделение снимается молча.
        coordinator.syncSelection(of: table, to: 99)
        #expect(table.selectedRow == -1)

        #expect(box.writes.isEmpty)
    }

    @Test("сокращение списка, в котором выделенной строки больше нет, выбор не пишет")
    func shrinkingReloadDoesNotWrite() {
        let (table, coordinator, box) = makeTable(items: [10, 20, 30])
        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        box.writes.removeAll()

        coordinator.items = [Item(id: 10)]
        coordinator.withoutWritingSelection { table.reloadData() }
        coordinator.syncSelection(of: table, to: 30)

        #expect(table.selectedRow == -1)
        #expect(box.writes.isEmpty)
    }
}
