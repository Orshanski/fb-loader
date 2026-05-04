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
    var selectedAuthorID: Int32? = nil
    var selectedSeriesID: Int32? = nil
    var selectedGenreID: Int16? = nil
    var selectedBookLibid: Int32? = nil
    var languageFilter: String = "ru"
    var sidebarFilter: String = ""
    var checkedBookLibids: Set<Int32> = []

    /// Set to `true` from BooksTableView's context-menu action; observed by
    /// MainWindowView which runs the export and resets it back to false.
    var shouldStartExport: Bool = false

    /// Active export progress, if any. Drives the modal sheet.
    var exportProgress: ExportProgress? = nil

    func reset() {
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
