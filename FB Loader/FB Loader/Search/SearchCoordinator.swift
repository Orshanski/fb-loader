import Foundation
import Observation

/// Owns all state for one instance of the search-window sheet.
/// Recreated each time the sheet opens — no persistence between presentations.
///
/// `@Observable` so SwiftUI views can observe property changes.
/// `@MainActor` so all reads/writes happen on the main thread (the heavy
/// search work runs in `Task.detached` and publishes results back here on
/// MainActor).
@Observable
@MainActor
final class SearchCoordinator {
    // MARK: - Inputs

    /// Current text in the search field.
    var query: String = ""

    /// Local language filter; initialised from the main window's
    /// `AppState.languageFilter` at sheet-open time, then independent.
    var languageFilter: String

    // MARK: - Output / status

    /// True while a search is in progress (background task running).
    var isSearching: Bool = false

    /// Last completed search results. `nil` before the first search or
    /// after a clear-text reset.
    var results: SearchResults? = nil

    /// The query string that produced the current `results` — used for
    /// the "ничего не найдено по запросу X" empty-state message.
    var lastQuery: String = ""

    // MARK: - UI state (local to this window, NOT shared with main AppState)

    /// Books the user has checked for export within THIS window. Closing
    /// the sheet drops them on the floor.
    var checkedBookLibids: Set<Int32> = []

    /// Currently-highlighted book in the result list — drives the bottom
    /// detail panel.
    var selectedBookLibid: Int32? = nil

    /// Collapsed author-group blocks. Keys are indices into
    /// `Library.authors` (matching `AuthorMatch.authorIndex`).
    var collapsedAuthors: Set<Int> = []

    /// Collapsed series-group blocks. Keys are indices into `Library.series`.
    var collapsedSeries: Set<Int> = []

    /// Default visible counts per group. "Показать всех" sets to `.max`,
    /// "Загрузить ещё +20" increments by 20 for books.
    var visibleAuthorsCount: Int = 10
    var visibleSeriesCount: Int = 10
    var visibleBooksCount: Int = 20

    init(initialLanguage: String) {
        self.languageFilter = initialLanguage
    }

    /// Run a search against the library. Heavy CPU-bound scoring runs in
    /// a detached Task; results publish back on MainActor when done.
    func runSearch(in library: Library) async {
        let q = query
        if q.trimmingCharacters(in: .whitespaces).isEmpty {
            results = nil
            lastQuery = ""
            return
        }
        isSearching = true
        let lang = languageFilter
        let r = await Task.detached(priority: .userInitiated) {
            SearchEngine.run(query: q, language: lang, in: library)
        }.value
        results = r
        lastQuery = q
        isSearching = false
        // Reset per-result UI state so each new search starts fresh.
        collapsedAuthors.removeAll()
        collapsedSeries.removeAll()
        visibleAuthorsCount = 10
        visibleSeriesCount = 10
        visibleBooksCount = 20
        selectedBookLibid = nil
    }
}
