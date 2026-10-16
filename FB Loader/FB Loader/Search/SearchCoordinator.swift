import Foundation
import Observation
import SwiftUI

/// Recreated each time the sheet opens; nothing persists between presentations.
@Observable
@MainActor
final class SearchCoordinator {
    // MARK: - Inputs

    var query: String = ""

    /// Initialised from `AppState.languageFilter` at sheet-open time, then independent.
    /// Смена сбрасывает выдачу, отметки и превью: иначе блоки авторов/серий
    /// перефильтровались бы по новому языку, а найденный список остался бы от старого.
    var languageFilter: String {
        didSet {
            guard languageFilter != oldValue else { return }
            results = nil
            lastQuery = ""
            selectedBookLibid = nil
            checkedBookLibids.removeAll()
        }
    }

    // MARK: - Output / status

    var isSearching: Bool = false

    var results: SearchResults? = nil

    /// The query that produced `results`; shown in the empty-state message.
    var lastQuery: String = ""

    // MARK: - UI state (local to this window, NOT shared with main AppState)

    var checkedBookLibids: Set<Int32> = []

    var selectedBookLibid: Int32? = nil

    var collapsedAuthors: Set<Int> = []

    var collapsedSeries: Set<Int> = []

    var fullyExpandedAuthors: Set<Int> = []

    var fullyExpandedSeries: Set<Int> = []

    /// Default visible counts per group. "Показать всех" sets to `.max`,
    /// "Загрузить ещё +20" increments by 20 for books.
    var visibleAuthorsCount: Int = 10
    var visibleSeriesCount: Int = 10
    var visibleBooksCount: Int = 20

    init(initialLanguage: String) {
        self.languageFilter = initialLanguage
    }

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
        collapsedAuthors.removeAll()
        collapsedSeries.removeAll()
        fullyExpandedAuthors.removeAll()
        fullyExpandedSeries.removeAll()
        visibleAuthorsCount = 10
        visibleSeriesCount = 10
        visibleBooksCount = 20
        selectedBookLibid = nil
    }

    // MARK: - Per-book bindings (used by per-block views in the search sheet)

    /// Author and series blocks share `checkedBookLibids`, so the same book stays in sync in both.
    func bindingChecked(_ book: Book) -> Binding<Bool> {
        Binding(
            get: { self.checkedBookLibids.contains(book.libid) },
            set: { isOn in
                if isOn { self.checkedBookLibids.insert(book.libid) }
                else    { self.checkedBookLibids.remove(book.libid) }
            }
        )
    }

    /// Selection is global (one book across all blocks); writing `false` is a no-op on purpose so
    /// toggling another row off doesn't blank the detail panel.
    func bindingSelected(_ book: Book) -> Binding<Bool> {
        Binding(
            get: { self.selectedBookLibid == book.libid },
            set: { newValue in if newValue { self.selectedBookLibid = book.libid } }
        )
    }
}
