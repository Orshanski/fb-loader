import Foundation
import Observation

/// Top-level observable state. Owns the loaded `Library` and selection state.
/// Recreated by the app on launch.
@Observable
final class AppState {
    enum LoadStage {
        case starting
        case onboarding
        case loading(progress: String)
        case ready(Library)
        case failed(String)
    }

    var stage: LoadStage = .starting
    /// Shared single source of truth — same instance is read by SettingsView (§14).
    let userPaths = UserPaths.shared

    // UI selection state — explicitly NOT persisted (per spec §4 "Состояние между запусками").
    enum SidebarSelection: Equatable {
        case authors(Int32?)
        case series(Int32?)
        case genres(Int16?)
    }

    private(set) var sidebar: SidebarSelection = .authors(nil)
    var selectedBookLibid: Int32? = nil
    var languageFilter: String = "ru"
    var sidebarFilter: String = ""
    var checkedBookLibids: Set<Int32> = []

    /// Диапазон дат добавления, применённый кнопкой «Найти» в поповере
    /// колонки «Дата». `nil` — фильтра нет.
    private(set) var dateFilter: DateRangeFilter? = nil

    /// Пользовательский путь: «Найти» / «Сбросить» в поповере и крестик
    /// в шапке таблицы. Гасит галочки и превью — один раз, по нажатию.
    /// Смена автора/серии/жанра фильтр обнуляет НЕ через этот метод, а
    /// прямым присваиванием: там свои правила для превью.
    func applyDateFilter(_ next: DateRangeFilter?) {
        guard dateFilter != next else { return }
        dateFilter = next
        selectedBookLibid = nil
        checkedBookLibids.removeAll()
    }

    func selectSection(_ section: SidebarSelection) {
        guard sidebar != section else { return }
        sidebar = section
        selectedBookLibid = nil
        sidebarFilter = ""
        checkedBookLibids.removeAll()
        dateFilter = nil
    }

    func selectAuthor(_ id: Int32?, deepLinkName: String? = nil) {
        applyEntitySelection(.authors(id), deepLinkName: deepLinkName)
    }

    func selectSeries(_ id: Int32?, deepLinkName: String? = nil) {
        applyEntitySelection(.series(id), deepLinkName: deepLinkName)
    }

    func selectGenre(_ id: Int16?) {
        applyEntitySelection(.genres(id), deepLinkName: nil)
    }

    private func applyEntitySelection(_ next: SidebarSelection, deepLinkName: String?) {
        if let name = deepLinkName {
            // Сценарий 2: deep-link с прицельным фильтром, preview сохраняется.
            // dateFilter гасится присваиванием, а не applyDateFilter — тот
            // обнулил бы selectedBookLibid, который здесь обязан выжить.
            sidebar = next
            sidebarFilter = name
            checkedBookLibids.removeAll()
            dateFilter = nil
            return
        }
        // Сценарий 3: клик в списке.
        guard sidebar != next else { return }
        sidebar = next
        selectedBookLibid = nil
        checkedBookLibids.removeAll()
        dateFilter = nil
    }

    /// Set to `true` from BooksTableView's context-menu action; observed by
    /// MainWindowView which runs the export and resets it back to false.
    var shouldStartExport: Bool = false

    /// Active export progress, if any. Drives the modal sheet.
    var exportProgress: ExportProgress? = nil

    func reset() {
        sidebar = .authors(nil)
        selectedBookLibid = nil
        languageFilter = "ru"
        sidebarFilter = ""
        checkedBookLibids.removeAll()
        dateFilter = nil
    }
}
