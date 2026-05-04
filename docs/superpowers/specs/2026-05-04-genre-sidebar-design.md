# Genre Sidebar Search Design

## Context

FB Loader currently has two left-sidebar modes: `Авторы` and `Серии`.
Both modes share the same language filter and text filter, and both drive the
books table by setting selection state in `AppState`.

The app already stores genre metadata in `Library.genres`, including
`Genre.parentID`, and each `Book` stores `genreIDs`. The books table already
renders book genre names through `library.genreByID`.

## Goal

Add a third left-sidebar mode, `Жанры`, for browsing and searching books by
genre.

## UI Behavior

- Add `Жанры` as the third segment in the existing sidebar segmented control:
  `Авторы | Серии | Жанры`.
- Keep the existing language picker to the right of the segmented control.
- Keep the existing `Фильтр` text field below the controls.
- Do not change the current minimum width of the left sidebar.
- In `Жанры` mode, show genres as an always-expanded grouped list:
  - root genres are bold selectable rows;
  - child genres are indented selectable rows;
  - there is no expand/collapse state and no disclosure control.
- Selecting any genre row shows books that have that exact genre ID. This
  includes root genres: choosing `Фантастика` does not aggregate child genres
  and will show an empty books table when there are no books tagged directly
  with the root genre ID.
- The language filter applies to genre counters and to the books shown for the
  selected genre.
- Genre rows with count `0` under the active language are hidden, matching the
  existing sidebar filter component behavior for authors and series.
- The text filter searches genre names through the existing sidebar filter
  component; no separate genre-specific search implementation is added.
- If the text filter matches no genres, the genre list is empty: do not show
  unmatched rows and do not add a special empty-state message.

## Data Model

Extend `AppState.SidebarTab` with `genres` and add `selectedGenreID: Int16?`.
Switching modes does not need to clear the other stored selections; existing
selection checks should remain gated by the active tab, as they are for authors
and series.

Extend `Library` with secondary genre indices:

- `booksByGenre: [Int16: [Int]]`
- `bookCountByGenre: [Int16: Int]`
- `bookCountByGenreByLang: [Int16: [String: Int]]`
- `childGenresByParent: [Int16: [Genre]]`
- `rootGenres: [Genre]`
- `orphanGenres: [Genre]`
- `sidebarGenres: [Genre]`
- `lowercasedGenreNames: [Int16: String]`
- `lowercasedSidebarGenreNames: [String]`

The genre tree should be derived from `Genre.parentID`. This implementation
supports the current bundled `genres.json` shape: root genres plus one child
level. A genre with `parentID == nil` is a root genre and is still selectable.
A genre whose parent is a known root is a selectable child genre. If future data
contains deeper nesting, flatten descendants under their nearest root and keep
them selectable. If a genre references a missing parent, show it as a selectable
top-level row.

## Books Lookup

Extend `BooksByContext.Context` with `genre(Int16)`. Genre lookup returns books
whose `book.genreIDs` contains the selected genre ID and whose language matches
the active language filter.

Root genre aggregation is intentionally out of scope: choosing `Фантастика`
does not show all fantasy books, only books tagged directly with the
`Фантастика` genre ID.

## Components

Add `GenresListView` under `UI/LeftSidebar`. It should reuse the existing
`FilteredSidebarList` component so genre filtering keeps the same debounced,
off-main behavior as authors and series.

`LeftSidebarView` routes `AppState.SidebarTab.genres` to `GenresListView`.
`BooksTableView` updates `visibleBooks` and the header/breadcrumb consistently
with existing sidebar modes: when a genre is selected, the header shows the
selected genre name.

## Testing

Add focused tests for:

- `Library` builds genre counts by language and books-by-genre indices.
- `BooksByContext.books(for: .genre(...))` returns exact-genre matches only and
  respects the language filter.
- Root genres are represented separately from child genres in the derived
  library indices.

UI behavior will be kept close to existing SwiftUI patterns; full UI automation
is not required for this change.
