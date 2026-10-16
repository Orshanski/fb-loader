import SwiftUI

struct SidebarRowStyle {
    var leadingInset: CGFloat = 14
    var fontWeight: NSFont.Weight = .regular
}

/// Sidebar list with a debounced, off-main name filter. Generic over the
/// item type so authors and series share one implementation.
///
/// `lowercasedNames` is a parallel array to `items` — the same length, the
/// same order. The Library pre-computes both so we can scan 100k+ entries
/// without re-allocating lowercased strings per keystroke.
///
/// `filterKey` lets the caller invalidate the filter task when an external
/// dependency (e.g. language filter) changes; whenever it differs from the
/// previous render, `.task(id:)` cancels the in-flight scan and starts over.
struct FilteredSidebarList<Item: Identifiable & Sendable>: View
where Item.ID: Hashable & Sendable {
    let items: [Item]
    let lowercasedNames: [String]
    let countFor: @Sendable (Item) -> Int
    let labelFor: (Item) -> String
    let trailingLabelFor: (Item) -> String
    var includeZeroCountItem: @Sendable (Item, NamePattern) -> Bool = { _, _ in false }
    var rowStyleFor: (Item) -> SidebarRowStyle = { _ in SidebarRowStyle() }
    @Binding var selectedID: Item.ID?
    let filterText: String
    let filterKey: String
    let memoryKey: String

    @Environment(\.sidebarMemory) private var memory
    @State private var filtered: [Item] = []
    @State private var computedKey: String?
    @State private var started = false

    var body: some View {
        LazyListTable(
            items: computedKey == nil ? (memory?.items(Item.self, filterKey: filterKey, for: memoryKey) ?? []) : filtered,
            selectedID: $selectedID,
            labelFor: labelFor,
            trailingLabelFor: trailingLabelFor,
            rowStyleFor: rowStyleFor,
            scrollMemory: memory,
            scrollKey: memoryKey,
            scrollFilterKey: filterKey
        )
        .task(id: filterKey) { await reloadFilter() }
    }

    /// Первый расчёт идёт без паузы, чтобы список не был пуст при показе раздела. Все следующие ждут 150 мс:
    /// `.task(id:)` отменяет предыдущую задачу, а отмена доходит и до фонового скана, так что сканы не копятся.
    private func reloadFilter() async {
        let first = !started
        started = true
        if computedKey == nil, let cached = memory?.items(Item.self, filterKey: filterKey, for: memoryKey) {
            filtered = cached
            computedKey = filterKey
            return
        }
        if !first {
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
        }

        let pattern = NamePattern(query: filterText)
        let items = items
        let names = lowercasedNames
        let count = countFor
        let includeZeroCountItem = includeZeroCountItem
        let scan = Task.detached(priority: .userInitiated) { () -> [Item]? in
            var out: [Item] = []
            out.reserveCapacity(64)
            for i in items.indices {
                if i & 0xFFF == 0, Task.isCancelled { return nil }
                let item = items[i]
                let itemCount = count(item)
                if itemCount > 0 && pattern.matches(names[i]) {
                    out.append(item)
                    continue
                }
                if !includeZeroCountItem(item, pattern) {
                    continue
                }
                out.append(item)
            }
            return out
        }
        let scanned = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
        guard let result = scanned, !Task.isCancelled else { return }
        filtered = result
        computedKey = filterKey
        memory?.store(result, filterKey: filterKey, for: memoryKey)
    }
}
