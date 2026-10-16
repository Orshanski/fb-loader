import Foundation
import Observation

/// Top-level observable state. Owns the loaded `Library` and selection state.
/// Recreated by the app on launch.
@Observable
final class AppState {
    enum LoadStage {
        case starting
        case onboarding(MissingPaths)
        case loading(progress: String)
        case ready(Library)
        case failed(String)
    }

    var stage: LoadStage = .starting

    /// Пересборка нужна, когда INPX подменили при открытом каталоге; на
    /// онбординге, во время загрузки и на экране ошибки её нет.
    var canRebuildCatalog: Bool {
        if case .ready = stage { true } else { false }
    }
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
    private(set) var languageFilter: String = "ru"
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

    /// Как в окне поиска: отмеченные и открытая книга остались бы от прежнего языка.
    func selectLanguage(_ language: String) {
        guard languageFilter != language else { return }
        languageFilter = language
        selectedBookLibid = nil
        checkedBookLibids.removeAll()
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

    let exportSession: ExportSession

    init(exportSession: ExportSession? = nil) {
        self.exportSession = exportSession
            ?? ExportSession(userPaths: UserPaths.shared, chooseFolder: ExportFolderPanel.choose)
    }

    /// Sheet настроек открыт. Живёт здесь, а не в ContentView: пока он открыт,
    /// пункты меню главного окна должны быть неактивны.
    var isSettingsPresented = false

    var isSearchPresented = false

    /// Любой модальный sheet главного окна (настройки, поиск, выбор папки, ход и итог выгрузки):
    /// пока он открыт, ⌘, не должна открывать ещё один.
    var isAnySheetPresented: Bool {
        isSettingsPresented || isSearchPresented || exportSession.isPresentingUI
    }

    func reset() {
        sidebar = .authors(nil)
        selectedBookLibid = nil
        languageFilter = "ru"
        sidebarFilter = ""
        checkedBookLibids.removeAll()
        dateFilter = nil
    }
}
