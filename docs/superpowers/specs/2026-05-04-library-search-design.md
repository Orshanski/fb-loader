# Offline Library Search Design

## Context

FB Loader currently has one primary browsing surface: the left sidebar. The
sidebar switches between `Авторы`, `Серии`, and `Жанры`, applies the current
language filter, and uses `Фильтр` only to narrow the active sidebar list.
Selecting a sidebar item drives `BooksTableView`; selecting a book opens
`BookDetailView` in the lower pane.

That model is good for browsing, but it is a poor fit for broad lookup. A user
who remembers only part of a title, author, or series should not have to guess
which sidebar tab to use. Search therefore needs to be separate from the sidebar
filter and must preserve its own context while the user inspects results.

## Goal

Add an offline library search window that searches across authors, series, and
books in the already-loaded local catalog. Search should be explicit, scoped by
language, and independent from sidebar browsing state.

The search implementation uses an app-owned token-based fuzzy scorer. It does
not add a third-party Swift search dependency.

## Non-Goals

- Do not replace the existing sidebar filter.
- Do not add online search or any network dependency for library data.
- Do not change normal sidebar browsing behavior for authors, series, or genres.
- Do not silently jump from search results into the main sidebar.
- Do not include an implementation plan in this document.

## Entry Point

Add a compact magnifying-glass button to the top row of `LeftSidebarView`, next
to the existing `Авторы | Серии | Жанры` segmented control and
`LanguageFilterPicker`.

The button opens a separate search window. `Cmd+F` may open the same window as a
secondary shortcut, but the visible sidebar button is the primary discoverable
entry point. Opening search must not alter the active sidebar tab, selected
author, selected series, selected genre, selected book, checked books, or the
sidebar filter text.

## Search Window

The search UI is a separate window without the main sidebar. It has:

- a standard macOS titlebar;
- one query field;
- a language picker initialized from the current main-window language filter;
- a `Поиск` button;
- a scrollable grouped results area;
- a lower book detail area that mirrors the existing `BookDetailView` concept.

The query runs only when the user presses `Поиск` or Enter. It does not run on
every keystroke. Closing the search window exits search without changing the
main window.

## Language Scope

Search is always scoped to one language. The initial language is copied from
`AppState.languageFilter` when the search window opens. The search window owns
its local language picker after that. Changing the language does not mutate the
main-window language filter and does not silently change sidebar results.

The selected language is applied when the user presses `Поиск` or Enter. If the
user changes language after results are shown, the existing results remain
visible but are considered stale until the next explicit search.

The language filter applies to:

- books shown under matched authors;
- books shown under matched series;
- direct book results;
- section counts such as `показано N из M`.

Author and series candidates may still be matched by name, but sections with no
books in the selected language are omitted from the final results.

The existing sentinel for missing language, `BooksByContext.unspecifiedLanguageToken`,
maps to the empty language string in catalog records.

## Results Model

Search produces grouped results, not a flat mixed list.

Author matches render as:

```text
АВТОР <matched author name>        показано N из M   Показать все
<that author's books in the selected language>
```

Series matches render as:

```text
СЕРИЯ <matched series name> · <author/context>       показано N из M   Показать все
<that series' books in the selected language>
```

Book matches render as:

```text
В ПОИСКЕ Совпадения по книгам       M книг
<directly matched books in the selected language>
```

Author and series sections include books directly underneath. They are not
selection shortcuts that jump to the main sidebar. The direct book section is
for books whose searchable text matched the query.

Initial result limits are:

- authors: 10 matched author sections;
- series: 10 matched series sections;
- books: 100 direct book rows;
- books shown inside each matched author or series section: a small initial
  slice, with `Показать еще` or `Показать все` available for expansion.

## Book Rows and Book Detail

Book rows in search should visually follow `BooksTableView`: checkbox, title,
series number, file size, date, and genres. Column widths and typography should
stay close to the existing table so search results feel like the same app.

The checkbox keeps the same meaning as in the main table: it edits the global
export selection, `AppState.checkedBookLibids`. Opening search does not alter
checked books, but explicitly checking or unchecking a book in search changes
the same export selection the main window uses.

Clicking a book row selects that row and opens the book detail area at the
bottom of the search window. This detail area should reuse the same conceptual
layout as `BookDetailView`: cover, title, metadata line, author chips, series
chip, and annotation.

Clicking a book row does not close search and does not navigate the main window.

## Leaving Search

Search remains isolated while the user clicks result sections and book rows.

The explicit in-content navigation actions that leave search are the clickable
pills inside the selected book detail:

- author pill: close search, switch the main sidebar to `Авторы`, select that
  author, and show that author's books in the main `BooksTableView`;
- series pill: close search, switch the main sidebar to `Серии`, select that
  series, and show that series in the main `BooksTableView`.

This makes the transition understandable: the user leaves search because they
clicked a normal app-navigation pill, not because selecting a result silently
changed the main window context.

## Search Index

Build an app-owned `LibrarySearchIndex` from the loaded `Library`. The index is
local and derived only from the binary library cache.

Searchable candidates:

- author candidate: `displayName`;
- series candidate: `series.name` plus all unique author names from books in
  that series, in stable first-seen book order;
- book candidate: `book.title` plus book authors plus series name.

Each candidate stores:

- stable entity id;
- original display text;
- normalized token array;
- language for book candidates.

Authors and series are language-neutral candidates, but their final result
sections are filtered out if they have no books in the selected language.

Series section display uses the first few unique author names from the same
stable first-seen order, followed by a compact overflow marker when needed.

The index may be built eagerly after the library loads or lazily when search is
first opened. This is a one-time preparation step for a given library snapshot,
so startup visibility matters more than shaving every millisecond off index
construction. The UI should expose progress if the build is long enough to be
noticed.

Prototype timing on the current local cache:

- catalog size: 167453 authors, 69007 series, 581134 books;
- binary decode: about 0.8-1.0 seconds;
- search index build: about 13.1 seconds;
- full scan search across authors, series, and books: about 4.6-7.5 seconds for
  tested Russian queries.

These numbers are acceptable for validating the approach because search is
button-triggered and index construction is one-time. They should still be
measured in the app during implementation.

## Matching Algorithm

Use a token-based fuzzy scorer based on the approach already used by
`librarium-py`, adapted into FB Loader's Swift code.

Normalization:

- lowercase;
- replace `ё` with `е`;
- replace non-letter and non-number runs with spaces;
- collapse and trim whitespace;
- split into tokens.

Scoring:

- split the query and candidate into normalized tokens;
- for each query token, find the best matching candidate token;
- score one token pair from the minimum of:
  - query-side LCS coverage;
  - LCS-derived indel ratio similarity;
- the candidate score is the minimum score across all query tokens.

For token strings `q` and `c`, with `lcs = LCS(q, c)`:

- query-side LCS coverage is `lcs / q.count * 100`;
- LCS-derived indel ratio is `2 * lcs / (q.count + c.count) * 100`.

Using the minimum across query tokens is intentional. It prevents a candidate
from ranking highly because it matched only the easy part of a multi-token query
such as `павел почика` or `сломаный меч`.

The initial cutoff is 75, matching the proven `librarium-py` behavior. Exact
cutoffs may be tuned during implementation with tests and real catalog samples.
Result ordering should be stable: score descending, then normalized display
text/title ascending, then stable entity id ascending.

## Library Decision

Do not use `FuzzyMatch` or another Swift fuzzy-search package for this feature.

Verified investigation:

- `FuzzyMatch` documentation and package metadata were checked through the Swift
  package registry, Swift Package Index, GitHub, and Context7.
- `FuzzyMatch` works for single-token surname-style queries, but its default
  ranking is a poor fit for multi-token Russian queries such as
  `имя + обрезанная фамилия`.
- The app-owned `librarium-py` style scorer returned the expected author first
  for tested multi-token cases where `FuzzyMatch` often returned unrelated
  results or no useful result.
- `fuse-swift` was also checked and is archived.

References reviewed during design:

- `https://swiftpackageregistry.com/ordo-one/FuzzyMatch`
- `https://swiftpackageindex.com/ordo-one/FuzzyMatch`
- `https://github.com/ordo-one/FuzzyMatch`
- `https://github.com/krisk/fuse-swift`
- `/Users/alexey/code/librarium-py/backend/app/search.py`

The resulting architecture keeps the scorer behind app-owned search types so it
can be optimized without changing the search window UI.

## Performance Direction

The first implementation can use a full scan over precomputed tokens. That keeps
the behavior simple and measurable.

Potential optimizations are internal to `LibrarySearchIndex` and do not change
the user-facing design:

- cache normalized token arrays;
- avoid repeated lookup of book authors and series names during search;
- keep `bookByLibid` for O(1) result materialization;
- add a token prefilter or inverted index if full scans become too slow;
- run search off the main actor and publish results back to SwiftUI.

Search should show a busy state while running. Because the query is
button-triggered, multi-second searches are acceptable for the initial feature
as long as the UI remains responsive.

## Architecture

Introduce search as a separate layer from sidebar selection:

- `LibrarySearchIndex` owns normalized candidates derived from `Library`.
- `LibrarySearchService` accepts query text and language scope, runs matching,
  applies final language filtering and limits, and returns grouped results.
- `LibrarySearchWindowState` owns query text, selected language, current
  results, expanded sections, selected book, and busy/error state.
- The search window reads `Library` and existing lookup dictionaries but does
  not mutate sidebar state except through explicit author/series pill
  navigation.

The search result model should carry enough book data for rows and detail
selection without requiring repeated whole-library scans during rendering.

## Error Handling

If the index is still building, the search window shows a progress or busy state
and disables `Поиск`.

If the query normalizes to no tokens, results are cleared and no search runs.

If no results match, the results area shows a neutral empty state.

If a selected result refers to an entity that is missing from the current
library snapshot, omit that row or section rather than crashing. This is
defensive only; normal library loading should keep ids consistent.

## Testing Expectations

The implementation plan should include tests for:

- normalization, including case folding, punctuation, whitespace, and `ё`/`е`;
- token pair scoring and multi-token minimum scoring;
- Russian author queries with reversed order such as `имя + фамилия`;
- prefix-like incomplete title queries such as `сломаный меч`;
- language filtering for direct books and author/series sections;
- grouped result limits and expansion state;
- search-window state isolation from sidebar filter and sidebar selection;
- explicit author/series pill navigation back to the main window.
