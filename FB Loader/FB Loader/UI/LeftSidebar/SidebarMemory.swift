import SwiftUI

/// Переживает скрытие сайдбара (его view уничтожается): результат фильтра и прокрутка каждого раздела.
/// Живёт в `@State` `MainWindowView`, а тот пересоздаётся при каждой загрузке каталога
/// (`ContentView` уходит через `.loading`), поэтому элементы чужой `Library` сюда не попадают.
final class SidebarMemory {
    private var results: [String: (filterKey: String, items: Any)] = [:]
    private var scrolls: [String: (filterKey: String, y: CGFloat)] = [:]

    func store<Item>(_ items: [Item], filterKey: String, for section: String) {
        results[section] = (filterKey, items)
    }

    func items<Item>(_: Item.Type, filterKey: String, for section: String) -> [Item]? {
        guard let r = results[section], r.filterKey == filterKey else { return nil }
        return r.items as? [Item]
    }

    /// Прокрутка относится к списку конкретного фильтра: на другом списке тот же y указывал бы не туда.
    func setScroll(_ y: CGFloat, filterKey: String, for section: String) {
        scrolls[section] = (filterKey, y)
    }

    func scroll(filterKey: String, for section: String) -> CGFloat? {
        guard let s = scrolls[section], s.filterKey == filterKey else { return nil }
        return s.y
    }
}

extension EnvironmentValues {
    @Entry var sidebarMemory: SidebarMemory? = nil
}
