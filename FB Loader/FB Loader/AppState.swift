import Foundation
import Observation

/// Top-level observable state. Owns the loaded `Library` and selection state.
/// Recreated by the app on launch.
@Observable
final class AppState {
    enum LoadStage {
        case onboarding
        case loading(progress: String)
        case ready(Library)
        case failed(String)
    }

    var stage: LoadStage = .onboarding
    /// Shared single source of truth — same instance is read by SettingsView (§14).
    let userPaths = UserPaths.shared

    // UI selection state — explicitly NOT persisted (per spec §4 "Состояние между запусками").
    enum SidebarTab { case authors, series }
    var sidebarTab: SidebarTab = .authors
    var selectedAuthorID: Int32? = nil
    var selectedSeriesID: Int32? = nil
    var selectedBookLibid: Int32? = nil
    var languageFilter: String = "ru"
    var sidebarFilter: String = ""
    var checkedBookLibids: Set<Int32> = []

    // Export-driven state (`shouldStartExport`, `exportProgress`) is added in
    // Phase 12 once `ExportProgress` is defined. Splitting AppState declaration
    // here keeps Phase 8 buildable without a forward reference.

    func reset() {
        sidebarTab = .authors
        selectedAuthorID = nil
        selectedSeriesID = nil
        selectedBookLibid = nil
        languageFilter = "ru"
        sidebarFilter = ""
        checkedBookLibids.removeAll()
    }
}
