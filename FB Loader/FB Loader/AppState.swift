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
    enum SidebarTab { case authors, series, genres }
    var sidebarTab: SidebarTab = .authors

    enum SidebarSelection: Equatable {
        case authors(Int32?)
        case series(Int32?)
        case genres(Int16?)
    }

    private(set) var sidebar: SidebarSelection = .authors(nil)
    var selectedAuthorID: Int32? = nil
    var selectedSeriesID: Int32? = nil
    var selectedGenreID: Int16? = nil
    var selectedBookLibid: Int32? = nil
    var languageFilter: String = "ru"
    var sidebarFilter: String = ""
    var checkedBookLibids: Set<Int32> = []

    func selectSection(_ section: SidebarSelection) {
        guard sidebar != section else { return }
        sidebar = section
        selectedBookLibid = nil
        sidebarFilter = ""
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
            sidebar = next
            sidebarFilter = name
            checkedBookLibids.removeAll()
            return
        }
        // Сценарий 3: клик в списке.
        guard sidebar != next else { return }
        sidebar = next
        selectedBookLibid = nil
        checkedBookLibids.removeAll()
    }

    /// Set to `true` from BooksTableView's context-menu action; observed by
    /// MainWindowView which runs the export and resets it back to false.
    var shouldStartExport: Bool = false

    /// Active export progress, if any. Drives the modal sheet.
    var exportProgress: ExportProgress? = nil

    func reset() {
        sidebar = .authors(nil)
        sidebarTab = .authors
        selectedAuthorID = nil
        selectedSeriesID = nil
        selectedGenreID = nil
        selectedBookLibid = nil
        languageFilter = "ru"
        sidebarFilter = ""
        checkedBookLibids.removeAll()
    }
}
