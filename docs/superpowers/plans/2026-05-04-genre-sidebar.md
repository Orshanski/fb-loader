# Genre Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Жанры` as a third left-sidebar mode that lets users browse exact-genre book matches with the existing language and text filters.

**Architecture:** Extend the existing `Library` snapshot with genre lookup indices, then route a new `BooksByContext.Context.genre` through the same table flow used by authors and series. Add a focused `GenresListView` because the genre list is grouped by parent/child rows and should not hide zero-count rows.

**Tech Stack:** Swift, SwiftUI, Swift Testing, Xcode/macOS target.

---

## File Map

- Modify `FB Loader/FB Loader/Models/Library.swift`: build genre indices and derived grouped genre data at load time.
- Modify `FB Loader/FB Loader/UI/BooksTable/BooksByContext.swift`: add exact genre lookup.
- Modify `FB Loader/FB Loader/AppState.swift`: add `genres` sidebar tab and `selectedGenreID`.
- Modify `FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift`: add the `Жанры` segment and route to `GenresListView`.
- Create `FB Loader/FB Loader/UI/LeftSidebar/GenresListView.swift`: render always-expanded grouped genre rows and filter by genre names.
- Modify `FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift`: show genre books and genre breadcrumb/header.
- Modify `FB Loader/FB LoaderTests/BooksByContextTests.swift`: cover genre indices and exact-genre lookup.

## Task 1: Add Failing Genre Lookup Tests

**Files:**
- Modify: `FB Loader/FB LoaderTests/BooksByContextTests.swift`

- [ ] **Step 1: Add tests for genre indices and exact lookup**

Append these tests inside `BooksByContextTests`:

```swift
@Test("library builds genre indices and language-aware counts")
func genreIndices() {
    let genres = [
        Genre(id: 1, code: "", name: "Фантастика", parentID: nil),
        Genre(id: 100, code: "sf", name: "Научная фантастика", parentID: 1),
        Genre(id: 101, code: "sf_fantasy", name: "Фэнтези", parentID: 1),
        Genre(id: 1001, code: "sf_deep", name: "Поджанр НФ", parentID: 100),
        Genre(id: 9000, code: "orphan", name: "Без родителя", parentID: 999),
    ]
    let books = [
        Book(libid: 10, title: "Root", authorIDs: [1], seriesID: nil,
             seriesNum: nil, genreIDs: [1], language: "ru",
             archiveIndex: 0, size: 0, dateAddedDays: 0),
        Book(libid: 11, title: "SF RU", authorIDs: [1], seriesID: nil,
             seriesNum: nil, genreIDs: [100], language: "ru",
             archiveIndex: 0, size: 0, dateAddedDays: 0),
        Book(libid: 12, title: "SF EN", authorIDs: [1], seriesID: nil,
             seriesNum: nil, genreIDs: [100], language: "en",
             archiveIndex: 0, size: 0, dateAddedDays: 0),
        Book(libid: 13, title: "Both", authorIDs: [1], seriesID: nil,
             seriesNum: nil, genreIDs: [100, 101], language: "ru",
             archiveIndex: 0, size: 0, dateAddedDays: 0),
    ]
    let lib = Library(
        inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
        authors: [Author(id: 1, lastName: "A", firstName: "", middleName: "")],
        series: [], genres: genres, books: books)

    #expect(lib.rootGenres.map(\.id) == [1])
    #expect(lib.childGenresByParent[1]?.map(\.id) == [100, 1001, 101])
    #expect(lib.orphanGenres.map(\.id) == [9000])
    #expect(lib.booksByGenre[1] == [0])
    #expect(lib.booksByGenre[100] == [1, 2, 3])
    #expect(lib.bookCountByGenreByLang[100]?["ru"] == 2)
    #expect(lib.bookCountByGenreByLang[100]?["en"] == 1)
    #expect(lib.bookCountByGenreByLang[101]?["en"] == nil)
}

@Test("genre context returns exact genre matches and respects language")
func genreContextExactLanguage() {
    let lib = Library(
        inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
        authors: [Author(id: 1, lastName: "A", firstName: "", middleName: "")],
        series: [],
        genres: [
            Genre(id: 1, code: "", name: "Фантастика", parentID: nil),
            Genre(id: 100, code: "sf", name: "Научная фантастика", parentID: 1),
        ],
        books: [
            Book(libid: 20, title: "Root", authorIDs: [1], seriesID: nil,
                 seriesNum: nil, genreIDs: [1], language: "ru",
                 archiveIndex: 0, size: 0, dateAddedDays: 0),
            Book(libid: 21, title: "Child RU", authorIDs: [1], seriesID: nil,
                 seriesNum: nil, genreIDs: [100], language: "ru",
                 archiveIndex: 0, size: 0, dateAddedDays: 0),
            Book(libid: 22, title: "Child EN", authorIDs: [1], seriesID: nil,
                 seriesNum: nil, genreIDs: [100], language: "en",
                 archiveIndex: 0, size: 0, dateAddedDays: 0),
        ])

    #expect(BooksByContext.books(for: .genre(1), language: "ru", in: lib).map(\.libid) == [20])
    #expect(BooksByContext.books(for: .genre(100), language: "ru", in: lib).map(\.libid) == [21])
    #expect(BooksByContext.books(for: .genre(100), language: "en", in: lib).map(\.libid) == [22])
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
cd "FB Loader" && xcodebuild -scheme "FB Loader" -destination 'platform=macOS' test -only-testing:"FB LoaderTests/BooksByContextTests"
```

Expected: FAIL because `Library` has no genre index properties and `BooksByContext.Context` has no `.genre`.

## Task 2: Implement Genre Indices and Exact Lookup

**Files:**
- Modify: `FB Loader/FB Loader/Models/Library.swift`
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksByContext.swift`

- [ ] **Step 1: Add genre index properties to `Library`**

In `Library.swift`, add stored properties near the existing secondary indices:

```swift
let booksByGenre: [Int16: [Int]]
let bookCountByGenre: [Int16: Int]
let bookCountByGenreByLang: [Int16: [String: Int]]
let rootGenres: [Genre]
let childGenresByParent: [Int16: [Genre]]
let orphanGenres: [Genre]
let lowercasedGenreNames: [Int16: String]
```

- [ ] **Step 2: Build the indices in `Library.init`**

After the existing author/series language-count loop, build genre indices with this logic:

```swift
var byGenre: [Int16: [Int]] = [:]
var byGenreLang: [Int16: [String: Int]] = [:]
for (i, b) in books.enumerated() {
    for gid in b.genreIDs {
        byGenre[gid, default: []].append(i)
        byGenreLang[gid, default: [:]][b.language, default: 0] += 1
    }
}
self.booksByGenre = byGenre
self.bookCountByGenre = byGenre.mapValues(\.count)
self.bookCountByGenreByLang = byGenreLang
```

Then derive grouped genre data:

```swift
let rootGenres = genres.filter { $0.parentID == nil }
let rootIDs = Set(rootGenres.map(\.id))
let parentByID = Dictionary(uniqueKeysWithValues: genres.map { ($0.id, $0.parentID) })

func nearestRootID(for genre: Genre) -> Int16? {
    var seen = Set<Int16>()
    var current = genre.parentID
    while let id = current {
        if rootIDs.contains(id) { return id }
        if seen.contains(id) { return nil }
        seen.insert(id)
        current = parentByID[id] ?? nil
    }
    return nil
}

self.rootGenres = rootGenres
var childrenByRoot: [Int16: [Genre]] = [:]
var orphans: [Genre] = []
for genre in genres where genre.parentID != nil {
    if let rootID = nearestRootID(for: genre) {
        childrenByRoot[rootID, default: []].append(genre)
    } else {
        orphans.append(genre)
    }
}
self.childGenresByParent = childrenByRoot.mapValues { children in
    children.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}
self.orphanGenres = orphans.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
self.lowercasedGenreNames = Dictionary(uniqueKeysWithValues: genres.map { ($0.id, $0.name.lowercased()) })
```

- [ ] **Step 3: Extend `BooksByContext`**

In `BooksByContext.swift`, change the enum and switch:

```swift
enum Context { case author(Int32), series(Int32), genre(Int16) }
```

```swift
switch ctx {
case .author(let id): indices = lib.booksByAuthor[id] ?? []
case .series(let id): indices = lib.booksBySeries[id] ?? []
case .genre(let id): indices = lib.booksByGenre[id] ?? []
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run:

```bash
cd "FB Loader" && xcodebuild -scheme "FB Loader" -destination 'platform=macOS' test -only-testing:"FB LoaderTests/BooksByContextTests"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/Models/Library.swift" "FB Loader/FB Loader/UI/BooksTable/BooksByContext.swift" "FB Loader/FB LoaderTests/BooksByContextTests.swift"
git commit -m "feat: add exact genre lookup indices"
```

## Task 3: Add Genre Sidebar State and View

**Files:**
- Modify: `FB Loader/FB Loader/AppState.swift`
- Modify: `FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift`
- Create: `FB Loader/FB Loader/UI/LeftSidebar/GenresListView.swift`

- [ ] **Step 1: Extend sidebar state**

In `AppState.swift`, update `SidebarTab` and add selected genre state:

```swift
enum SidebarTab { case authors, series, genres }
var selectedGenreID: Int16? = nil
```

In `reset()`, add:

```swift
selectedGenreID = nil
```

- [ ] **Step 2: Create `GenresListView.swift`**

Create `FB Loader/FB Loader/UI/LeftSidebar/GenresListView.swift`:

```swift
import SwiftUI

struct GenresListView: View {
    let library: Library
    let filterText: String
    let languageFilter: String
    @Binding var selectedGenreID: Int16?

    private var langKey: String {
        languageFilter == BooksByContext.unspecifiedLanguageToken ? "" : languageFilter
    }

    private var pattern: NamePattern { NamePattern(query: filterText) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(library.rootGenres) { root in
                    let children = matchingChildren(for: root)
                    if filterText.isEmpty || !children.isEmpty || matches(root) {
                        GenreRow(genre: root,
                                 count: count(for: root),
                                 isSelected: selectedGenreID == root.id,
                                 isRoot: true) {
                            selectedGenreID = root.id
                        }
                    }
                    ForEach(children) { child in
                        GenreRow(genre: child,
                                 count: count(for: child),
                                 isSelected: selectedGenreID == child.id,
                                 isRoot: false) {
                            selectedGenreID = child.id
                        }
                    }
                }
                ForEach(matchingOrphans()) { genre in
                    GenreRow(genre: genre,
                             count: count(for: genre),
                             isSelected: selectedGenreID == genre.id,
                             isRoot: true) {
                        selectedGenreID = genre.id
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func matchingChildren(for root: Genre) -> [Genre] {
        let children = library.childGenresByParent[root.id] ?? []
        guard !filterText.isEmpty else { return children }
        return children.filter { matches($0) }
    }

    private func matchingOrphans() -> [Genre] {
        guard !filterText.isEmpty else { return library.orphanGenres }
        return library.orphanGenres.filter { matches($0) }
    }

    private func matches(_ genre: Genre) -> Bool {
        guard let name = library.lowercasedGenreNames[genre.id] else { return false }
        return pattern.matches(name)
    }

    private func count(for genre: Genre) -> Int {
        library.bookCountByGenreByLang[genre.id]?[langKey] ?? 0
    }
}

private struct GenreRow: View {
    let genre: Genre
    let count: Int
    let isSelected: Bool
    let isRoot: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(genre.name)
                .font(.system(size: 13, weight: isRoot ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text("\(count)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.leading, isRoot ? 16 : 34)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
```

- [ ] **Step 3: Route `Жанры` in `LeftSidebarView`**

Add the segment:

```swift
Text("Жанры").tag(AppState.SidebarTab.genres)
```

Add the switch case:

```swift
case .genres:
    GenresListView(library: library,
                   filterText: s.sidebarFilter,
                   languageFilter: s.languageFilter,
                   selectedGenreID: $s.selectedGenreID)
```

- [ ] **Step 4: Build**

The project uses synchronized filesystem groups, so creating
`GenresListView.swift` under `FB Loader/FB Loader/UI/LeftSidebar/` is enough;
do not add manual `PBXFileReference` / build phase entries unless the build
proves the file is not compiled.

Run:

```bash
cd "FB Loader" && xcodebuild -scheme "FB Loader" -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/AppState.swift" "FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift" "FB Loader/FB Loader/UI/LeftSidebar/GenresListView.swift"
git commit -m "feat: add genre sidebar list"
```

## Task 4: Wire Genre Selection Into the Books Table

**Files:**
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift`

- [ ] **Step 1: Extend `visibleBooks`**

In `BooksTableView.visibleBooks`, add:

```swift
if let gid = state.selectedGenreID, state.sidebarTab == .genres {
    return BooksByContext.books(for: .genre(gid),
                                language: state.languageFilter,
                                in: library)
}
```

- [ ] **Step 2: Extend the breadcrumb/header**

In `breadcrumbRow`, change the fallback text to:

```swift
Text("Выберите автора, серию или жанр").foregroundStyle(.secondary)
```

In `breadcrumbLabel`, add:

```swift
if state.sidebarTab == .genres,
   let gid = state.selectedGenreID,
   let genre = library.genreByID[gid] {
    return ("Жанр", genre.name)
}
```

- [ ] **Step 3: Run tests**

Run:

```bash
cd "FB Loader" && xcodebuild -scheme "FB Loader" -destination 'platform=macOS' test -only-testing:"FB LoaderTests/BooksByContextTests"
```

Expected: PASS.

- [ ] **Step 4: Build**

Run:

```bash
cd "FB Loader" && xcodebuild -scheme "FB Loader" -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift"
git commit -m "feat: show books for selected genre"
```

## Task 5: Final Verification, Code Review, and Manual Test Gate

**Files:**
- None

- [ ] **Step 1: Run the full unit test suite**

Run:

```bash
cd "FB Loader" && xcodebuild -scheme "FB Loader" -destination 'platform=macOS' test
```

Expected: TEST SUCCEEDED. Do not run UI tests separately unless needed.

- [ ] **Step 2: Build the app**

Run:

```bash
cd "FB Loader" && xcodebuild -scheme "FB Loader" -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Request code review**

Before handing off for manual testing, request one code-review subagent review
of the implementation diff. The review must cover production code, tests, and
spec compliance. It must not push, close beads issues, or make edits directly.

Reviewer prompt:

```text
Review the genre sidebar implementation against:
- docs/superpowers/specs/2026-05-04-genre-sidebar-design.md
- docs/superpowers/plans/2026-05-04-genre-sidebar.md

Focus on correctness, regressions, missing tests, performance risks, and
SwiftUI behavior. Return findings only, ordered by severity. Do not edit files.
```

- [ ] **Step 4: Resolve review findings**

Fix Critical and Important findings before manual testing. For each fix, run
the narrowest relevant `xcodebuild test` command first, then rerun:

```bash
cd "FB Loader" && xcodebuild -scheme "FB Loader" -destination 'platform=macOS' test
cd "FB Loader" && xcodebuild -scheme "FB Loader" -destination 'platform=macOS' build
```

Expected: TEST SUCCEEDED and BUILD SUCCEEDED.

- [ ] **Step 5: Stop and hand off for manual testing**

Do not close `fb-loader-hsu`, do not push, and do not run release/publish steps
until the user manually tests the app and explicitly approves continuation.
Hand off the branch with:

```text
Ready for manual testing. Please verify:
- `Жанры` appears next to `Авторы` and `Серии`.
- Root genre rows are selectable and show exact-genre books only.
- Child genre rows are selectable and show exact-genre books only.
- Rows with 0 books under the active language remain visible.
- Filtering searches genre names and shows an empty genre list when no rows match.
- The books header shows the selected genre name.
```

## Task 6: Close and Push After Manual Approval

**Files:**
- Modify: `.beads/issues.jsonl`

- [ ] **Step 1: Close the beads issue after user approval**

Run only after the user says manual testing passed:

```bash
bd close fb-loader-hsu --reason="Genre sidebar design and implementation completed after manual testing."
```

- [ ] **Step 2: Stage beads export if sandbox warning appears**

Run:

```bash
git add .beads/issues.jsonl
```

- [ ] **Step 3: Commit closeout if needed**

If `.beads/issues.jsonl` changed after the last feature commit, run:

```bash
git add .beads/issues.jsonl
git commit -m "chore: close genre sidebar task"
```

- [ ] **Step 4: Push**

Run:

```bash
git pull --rebase
bd dolt push
git push
git status --short --branch
```

Expected: branch is up to date with origin and no uncommitted changes remain.
