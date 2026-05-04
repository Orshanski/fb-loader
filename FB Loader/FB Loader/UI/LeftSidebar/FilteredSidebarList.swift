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

    @State private var filtered: [Item] = []

    var body: some View {
        LazyListTable(
            items: filtered,
            selectedID: $selectedID,
            labelFor: labelFor,
            trailingLabelFor: trailingLabelFor,
            rowStyleFor: rowStyleFor
        )
        .task(id: filterKey) { await reloadFilter() }
    }

    /// 150 ms quiet window before scanning so rapid typing doesn't spawn
    /// N concurrent filter tasks; `.task(id:)` already handles cancel-and-
    /// restart on input change.
    private func reloadFilter() async {
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }

        let pattern = NamePattern(query: filterText)
        let items = items
        let names = lowercasedNames
        let count = countFor
        let includeZeroCountItem = includeZeroCountItem
        let result: [Item] = await Task.detached(priority: .userInitiated) {
            var out: [Item] = []
            out.reserveCapacity(64)
            for i in items.indices {
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
        }.value
        if Task.isCancelled { return }
        filtered = result
    }
}
