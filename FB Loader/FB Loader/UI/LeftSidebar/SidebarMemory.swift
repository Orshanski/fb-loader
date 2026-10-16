import SwiftUI

/// Переживает скрытие сайдбара (его view уничтожается): результат фильтра и прокрутка каждого раздела.
/// Привязана к экземпляру `Library`: на другой библиотеке старые элементы были бы чужими.
final class SidebarMemory {
    private weak var library: Library?
    private var results: [String: (filterKey: String, items: Any)] = [:]
    private var scrolls: [String: CGFloat] = [:]

    func bind(_ library: Library) {
        guard self.library !== library else { return }
        self.library = library
        results = [:]
        scrolls = [:]
    }

    func store<Item>(_ items: [Item], filterKey: String, for section: String) {
        results[section] = (filterKey, items)
    }

    func items<Item>(_: Item.Type, filterKey: String, for section: String) -> [Item]? {
        guard let r = results[section], r.filterKey == filterKey else { return nil }
        return r.items as? [Item]
    }

    func setScroll(_ y: CGFloat, for section: String) { scrolls[section] = y }
    func scroll(for section: String) -> CGFloat? { scrolls[section] }
}

extension EnvironmentValues {
    @Entry var sidebarMemory: SidebarMemory? = nil
}
