# Offline Library Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a separate offline search window for authors, series, and books using an app-owned token-based fuzzy scorer.

**Architecture:** Add a focused search layer (`LibrarySearchIndex`, `LibrarySearchService`) that derives normalized candidates from `Library` and returns grouped results scoped by language. Add a SwiftUI search window that owns query/results/detail state and only mutates main sidebar state through explicit author/series pills.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, existing `Library`, `Book`, `Author`, `Series`, `BooksByContext`, `BookDetailView`, no external fuzzy-search package.

---

## File Map

- Create `FB Loader/FB Loader/Search/LibrarySearchScorer.swift`  
  Pure normalization and scoring functions. No UI, no `Library` dependency.

- Create `FB Loader/FB Loader/Search/LibrarySearchIndex.swift`  
  Search candidate and index models built from `Library`.

- Create `FB Loader/FB Loader/Search/LibrarySearchService.swift`  
  Runs top-N matching, language filtering, stable sorting, and grouped result materialization.

- Create `FB Loader/FB Loader/UI/Search/LibrarySearchWindow.swift`  
  Search window shell: query field, language picker, button, busy state, results/detail split.

- Create `FB Loader/FB Loader/UI/Search/LibrarySearchResultsView.swift`  
  Grouped sections and book rows reused by the search window.

- Create `FB Loader/FB Loader/UI/Search/LibrarySearchWindowController.swift`  
  Opens one reusable `NSWindow` for search from the sidebar button and `Cmd+F`.

- Modify `FB Loader/FB Loader/UI/BookDetail/BookDetailView.swift`  
  Add an optional navigation callback so search can close after author/series pill navigation.

- Modify `FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift`  
  Add magnifying-glass entry button in the existing sidebar top row.

- Modify `FB Loader/FB Loader/FB_LoaderApp.swift`  
  Add `Cmd+F` command that opens the same search window.

- Test `FB Loader/FB LoaderTests/LibrarySearchScorerTests.swift`

- Test `FB Loader/FB LoaderTests/LibrarySearchServiceTests.swift`

- Test `FB Loader/FB LoaderUITests/FB_LoaderUITests.swift`

---

### Task 1: Token Scorer

**Files:**
- Create: `FB Loader/FB Loader/Search/LibrarySearchScorer.swift`
- Test: `FB Loader/FB LoaderTests/LibrarySearchScorerTests.swift`

- [ ] **Step 1: Write scorer tests**

Create `FB Loader/FB LoaderTests/LibrarySearchScorerTests.swift`:

```swift
import Testing
@testable import FB_Loader

@Suite("LibrarySearchScorer")
struct LibrarySearchScorerTests {
    @Test("normalizes Cyrillic text for search")
    func normalize() {
        #expect(LibrarySearchScorer.normalize("  Ёжик-в_тумане!!  ") == "ежик в тумане")
        #expect(LibrarySearchScorer.tokens("Сломаный меч") == ["сломаный", "меч"])
    }

    @Test("scores incomplete title tokens")
    func incompleteTitle() {
        let q = LibrarySearchScorer.tokens("сломаный меч")
        let c = LibrarySearchScorer.tokens("Сломанный меч")
        #expect(LibrarySearchScorer.tokenMinRatio(query: q, candidate: c) >= 75)
    }

    @Test("requires every query token to match")
    func everyQueryTokenMatters() {
        let q = LibrarySearchScorer.tokens("павел почика")
        let good = LibrarySearchScorer.tokens("Почикаев Павел")
        let bad = LibrarySearchScorer.tokens("Иванов Павел")
        #expect(LibrarySearchScorer.tokenMinRatio(query: q, candidate: good) >= 75)
        #expect(LibrarySearchScorer.tokenMinRatio(query: q, candidate: bad) < 75)
    }

    @Test("handles reversed author order")
    func reversedAuthorOrder() {
        let q = LibrarySearchScorer.tokens("дональд антрим")
        let c = LibrarySearchScorer.tokens("Антрим Дональд")
        #expect(LibrarySearchScorer.tokenMinRatio(query: q, candidate: c) == 100)
    }
}
```

- [ ] **Step 2: Run scorer tests and verify failure**

Run:

```bash
xcodebuild test -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" -only-testing:FB_LoaderTests/LibrarySearchScorerTests
```

Expected: fails because `LibrarySearchScorer` does not exist.

- [ ] **Step 3: Implement scorer**

Create `FB Loader/FB Loader/Search/LibrarySearchScorer.swift`:

```swift
import Foundation

enum LibrarySearchScorer {
    static let defaultCutoff = 75.0

    static func normalize(_ s: String) -> String {
        let lowered = s
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "Ё", with: "Е")
            .lowercased()
        var out = ""
        var previousWasSpace = true
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                previousWasSpace = false
            } else if !previousWasSpace {
                out.append(" ")
                previousWasSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokens(_ s: String) -> [String] {
        normalize(s)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    static func tokenMinRatio(query: [String], candidate: [String]) -> Double {
        guard !query.isEmpty && !candidate.isEmpty else { return 0 }
        var weakest = 100.0
        for queryToken in query {
            var best = 0.0
            for candidateToken in candidate {
                best = max(best, tokenMatchScore(queryToken, candidateToken))
            }
            weakest = min(weakest, best)
            if weakest < defaultCutoff { return weakest }
        }
        return weakest
    }

    static func tokenMatchScore(_ queryToken: String, _ candidateToken: String) -> Double {
        guard !queryToken.isEmpty && !candidateToken.isEmpty else { return 0 }
        let q = Array(queryToken)
        let c = Array(candidateToken)
        let lcs = lcsLength(q, c)
        let coverage = Double(lcs) / Double(q.count) * 100
        let ratio = Double(2 * lcs) / Double(q.count + c.count) * 100
        return min(coverage, ratio)
    }

    private static func lcsLength(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty && !b.isEmpty else { return 0 }
        var prev = Array(repeating: 0, count: b.count + 1)
        var curr = prev
        for ca in a {
            curr[0] = 0
            for (j, cb) in b.enumerated() {
                curr[j + 1] = ca == cb ? prev[j] + 1 : max(prev[j + 1], curr[j])
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}
```

- [ ] **Step 4: Run scorer tests and verify pass**

Run the same `xcodebuild test ... -only-testing:FB_LoaderTests/LibrarySearchScorerTests`.

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit scorer**

```bash
git add "FB Loader/FB Loader/Search/LibrarySearchScorer.swift" "FB Loader/FB LoaderTests/LibrarySearchScorerTests.swift"
git commit -m "feat: add library search scorer"
```

---

### Task 2: Search Index and Service

**Files:**
- Create: `FB Loader/FB Loader/Search/LibrarySearchIndex.swift`
- Create: `FB Loader/FB Loader/Search/LibrarySearchService.swift`
- Test: `FB Loader/FB LoaderTests/LibrarySearchServiceTests.swift`

- [ ] **Step 1: Write service tests**

Create `FB Loader/FB LoaderTests/LibrarySearchServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import FB_Loader

@Suite("LibrarySearchService")
struct LibrarySearchServiceTests {
    private func library() -> Library {
        Library(
            inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
            authors: [
                Author.unknown,
                Author(id: 1, lastName: "Андерсон", firstName: "Пол", middleName: ""),
                Author(id: 2, lastName: "Почикаев", firstName: "Павел", middleName: ""),
                Author(id: 3, lastName: "Олди", firstName: "Генри", middleName: "Лайон"),
            ],
            series: [
                Series(id: 10, name: "Сломанный меч"),
                Series(id: 11, name: "Бездна голодных глаз"),
            ],
            genres: [Genre(id: 100, code: "sf", name: "Фэнтези", parentID: nil)],
            books: [
                Book(libid: 101, title: "Сломанный меч", authorIDs: [1], seriesID: 10,
                     seriesNum: 1, genreIDs: [100], language: "ru", archiveIndex: 0,
                     size: 1000, dateAddedDays: 1),
                Book(libid: 102, title: "Broken Sword", authorIDs: [1], seriesID: 10,
                     seriesNum: 2, genreIDs: [100], language: "en", archiveIndex: 0,
                     size: 1000, dateAddedDays: 2),
                Book(libid: 103, title: "Почикаевская история", authorIDs: [2], seriesID: nil,
                     seriesNum: nil, genreIDs: [100], language: "ru", archiveIndex: 0,
                     size: 1000, dateAddedDays: 3),
                Book(libid: 104, title: "Шмагия", authorIDs: [3], seriesID: 11,
                     seriesNum: 1, genreIDs: [100], language: "ru", archiveIndex: 0,
                     size: 1000, dateAddedDays: 4),
            ])
    }

    @Test("finds direct book title matches scoped by language")
    func directBooksByLanguage() {
        let lib = library()
        let service = LibrarySearchService(index: LibrarySearchIndex(library: lib), library: lib)
        let result = service.search(query: "сломаный меч", language: "ru")
        #expect(result.books.map(\.book.libid) == [101])
        #expect(result.bookSectionsCount == 1)
    }

    @Test("finds reversed author query and includes only selected language books")
    func authorSectionLanguage() {
        let lib = library()
        let service = LibrarySearchService(index: LibrarySearchIndex(library: lib), library: lib)
        let result = service.search(query: "павел почика", language: "ru")
        #expect(result.authors.first?.author.id == 2)
        #expect(result.authors.first?.books.map(\.libid) == [103])
    }

    @Test("series sections are omitted when selected language has no books")
    func seriesLanguageOmission() {
        let lib = library()
        let service = LibrarySearchService(index: LibrarySearchIndex(library: lib), library: lib)
        let result = service.search(query: "бездна олди", language: "en")
        #expect(result.series.isEmpty)
    }
}
```

- [ ] **Step 2: Run service tests and verify failure**

Run:

```bash
xcodebuild test -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" -only-testing:FB_LoaderTests/LibrarySearchServiceTests
```

Expected: fails because search index/service types do not exist.

- [ ] **Step 3: Implement index models**

Create `FB Loader/FB Loader/Search/LibrarySearchIndex.swift`:

```swift
import Foundation

nonisolated struct LibrarySearchCandidate: Sendable, Identifiable {
    enum Kind: Sendable { case author, series, book }
    let id: Int32
    let kind: Kind
    let displayText: String
    let normalizedSortKey: String
    let tokens: [String]
    let language: String?
}

nonisolated struct LibrarySearchIndex: Sendable {
    let authors: [LibrarySearchCandidate]
    let series: [LibrarySearchCandidate]
    let books: [LibrarySearchCandidate]

    init(library: Library) {
        authors = library.authors
            .filter { $0.id != 0 }
            .map {
                LibrarySearchCandidate(
                    id: $0.id, kind: .author, displayText: $0.displayName,
                    normalizedSortKey: LibrarySearchScorer.normalize($0.displayName),
                    tokens: LibrarySearchScorer.tokens($0.displayName), language: nil)
            }

        series = library.series.map { series in
            let authorNames = Self.seriesAuthorNames(seriesID: series.id, library: library)
            let text = ([series.name] + authorNames).joined(separator: " ")
            return LibrarySearchCandidate(
                id: series.id, kind: .series, displayText: series.name,
                normalizedSortKey: LibrarySearchScorer.normalize(series.name),
                tokens: LibrarySearchScorer.tokens(text), language: nil)
        }

        books = library.books.map { book in
            let authorNames = book.authorIDs.compactMap { library.authorByID[$0]?.displayName }
            let seriesName = book.seriesID.flatMap { library.seriesByID[$0]?.name }
            let text = ([book.title] + authorNames + [seriesName].compactMap { $0 }).joined(separator: " ")
            return LibrarySearchCandidate(
                id: book.libid, kind: .book, displayText: book.title,
                normalizedSortKey: LibrarySearchScorer.normalize(book.title),
                tokens: LibrarySearchScorer.tokens(text), language: book.language)
        }
    }

    static func seriesAuthorNames(seriesID: Int32, library: Library) -> [String] {
        var seen = Set<Int32>()
        var names: [String] = []
        for index in library.booksBySeries[seriesID] ?? [] {
            for authorID in library.books[index].authorIDs where !seen.contains(authorID) {
                seen.insert(authorID)
                if let name = library.authorByID[authorID]?.displayName { names.append(name) }
            }
        }
        return names
    }
}
```

- [ ] **Step 4: Implement service**

Create `FB Loader/FB Loader/Search/LibrarySearchService.swift`:

```swift
import Foundation

nonisolated struct LibrarySearchResult: Sendable {
    let query: String
    let language: String
    let authors: [LibrarySearchAuthorSection]
    let series: [LibrarySearchSeriesSection]
    let books: [LibrarySearchBookHit]
    var bookSectionsCount: Int { books.count }
}

nonisolated struct LibrarySearchAuthorSection: Sendable, Identifiable {
    var id: Int32 { author.id }
    let author: Author
    let score: Double
    let shown: Int
    let total: Int
    let books: [Book]
}

nonisolated struct LibrarySearchSeriesSection: Sendable, Identifiable {
    var id: Int32 { series.id }
    let series: Series
    let authorContext: String
    let score: Double
    let shown: Int
    let total: Int
    let books: [Book]
}

nonisolated struct LibrarySearchBookHit: Sendable, Identifiable {
    var id: Int32 { book.libid }
    let book: Book
    let score: Double
}

nonisolated struct LibrarySearchService: Sendable {
    let index: LibrarySearchIndex
    let library: Library

    func search(query: String, language: String) -> LibrarySearchResult {
        let queryTokens = LibrarySearchScorer.tokens(query)
        guard !queryTokens.isEmpty else {
            return LibrarySearchResult(query: query, language: language, authors: [], series: [], books: [])
        }
        let langKey = language == BooksByContext.unspecifiedLanguageToken ? "" : language
        let authorHits = top(queryTokens, candidates: index.authors, limit: 80)
            .compactMap { authorSection($0, language: langKey) }
            .prefix(10)
        let seriesHits = top(queryTokens, candidates: index.series, limit: 80)
            .compactMap { seriesSection($0, language: langKey) }
            .prefix(10)
        let bookHits = top(queryTokens, candidates: index.books, limit: 100, language: langKey)
            .compactMap { hit -> LibrarySearchBookHit? in
                guard let book = library.bookByLibid[hit.candidate.id] else { return nil }
                return LibrarySearchBookHit(book: book, score: hit.score)
            }
        return LibrarySearchResult(
            query: query, language: language,
            authors: Array(authorHits), series: Array(seriesHits), books: bookHits)
    }

    private struct CandidateHit {
        let candidate: LibrarySearchCandidate
        let score: Double
    }

    private func top(
        _ queryTokens: [String],
        candidates: [LibrarySearchCandidate],
        limit: Int,
        language: String? = nil
    ) -> [CandidateHit] {
        var hits: [CandidateHit] = []
        hits.reserveCapacity(limit)
        for candidate in candidates {
            if let language, let candidateLanguage = candidate.language, candidateLanguage != language { continue }
            let score = LibrarySearchScorer.tokenMinRatio(query: queryTokens, candidate: candidate.tokens)
            guard score >= LibrarySearchScorer.defaultCutoff else { continue }
            let hit = CandidateHit(candidate: candidate, score: score)
            if hits.count < limit {
                hits.append(hit)
                if hits.count == limit { hits.sort(by: hitSort) }
            } else if hitSort(hit, hits[hits.count - 1]) {
                hits[hits.count - 1] = hit
                hits.sort(by: hitSort)
            }
        }
        hits.sort(by: hitSort)
        return hits
    }

    private func hitSort(_ lhs: CandidateHit, _ rhs: CandidateHit) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.candidate.normalizedSortKey != rhs.candidate.normalizedSortKey {
            return lhs.candidate.normalizedSortKey < rhs.candidate.normalizedSortKey
        }
        return lhs.candidate.id < rhs.candidate.id
    }

    private func authorSection(_ hit: CandidateHit, language: String) -> LibrarySearchAuthorSection? {
        guard let author = library.authorByID[hit.candidate.id] else { return nil }
        let books = (library.booksByAuthor[author.id] ?? [])
            .map { library.books[$0] }
            .filter { $0.language == language }
        guard !books.isEmpty else { return nil }
        return LibrarySearchAuthorSection(
            author: author, score: hit.score, shown: min(5, books.count),
            total: books.count, books: Array(books.prefix(5)))
    }

    private func seriesSection(_ hit: CandidateHit, language: String) -> LibrarySearchSeriesSection? {
        guard let series = library.seriesByID[hit.candidate.id] else { return nil }
        let books = (library.booksBySeries[series.id] ?? [])
            .map { library.books[$0] }
            .filter { $0.language == language }
            .sorted { ($0.seriesNum ?? Int16.max) < ($1.seriesNum ?? Int16.max) }
        guard !books.isEmpty else { return nil }
        let context = LibrarySearchIndex.seriesAuthorNames(seriesID: series.id, library: library)
            .prefix(4)
            .joined(separator: ", ")
        return LibrarySearchSeriesSection(
            series: series, authorContext: context, score: hit.score,
            shown: min(5, books.count), total: books.count, books: Array(books.prefix(5)))
    }
}
```

- [ ] **Step 5: Run service tests and full focused search tests**

Run:

```bash
xcodebuild test -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" -only-testing:FB_LoaderTests/LibrarySearchScorerTests -only-testing:FB_LoaderTests/LibrarySearchServiceTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Commit search service**

```bash
git add "FB Loader/FB Loader/Search" "FB Loader/FB LoaderTests/LibrarySearchServiceTests.swift"
git commit -m "feat: add offline library search service"
```

---

### Task 3: Search Window UI

**Files:**
- Create: `FB Loader/FB Loader/UI/Search/LibrarySearchWindow.swift`
- Create: `FB Loader/FB Loader/UI/Search/LibrarySearchResultsView.swift`
- Modify: `FB Loader/FB Loader/UI/BookDetail/BookDetailView.swift`

- [ ] **Step 1: Add search window state and shell**

Create `FB Loader/FB Loader/UI/Search/LibrarySearchWindow.swift`:

```swift
import SwiftUI

@Observable
final class LibrarySearchWindowState {
    var query = ""
    var language: String
    var result = LibrarySearchResult(query: "", language: "ru", authors: [], series: [], books: [])
    var selectedBookLibid: Int32?
    var isSearching = false
    let service: LibrarySearchService

    init(service: LibrarySearchService, initialLanguage: String) {
        self.service = service
        self.language = initialLanguage
    }

    @MainActor
    func search() {
        let q = query
        let lang = language
        guard !LibrarySearchScorer.tokens(q).isEmpty else {
            result = LibrarySearchResult(query: q, language: lang, authors: [], series: [], books: [])
            return
        }
        isSearching = true
        Task.detached {
            let next = service.search(query: q, language: lang)
            await MainActor.run {
                self.result = next
                self.isSearching = false
            }
        }
    }
}

struct LibrarySearchWindow: View {
    let library: Library
    let onNavigateOut: () -> Void
    @Environment(AppState.self) private var appState
    @State private var state: LibrarySearchWindowState

    init(library: Library, service: LibrarySearchService, initialLanguage: String, onNavigateOut: @escaping () -> Void) {
        self.library = library
        self.onNavigateOut = onNavigateOut
        _state = State(initialValue: LibrarySearchWindowState(service: service, initialLanguage: initialLanguage))
    }

    var body: some View {
        @Bindable var s = state
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Автор, серия или название книги", text: $s.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { state.search() }
                SearchLanguagePicker(library: library, language: $s.language)
                Button("Поиск") { state.search() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(state.isSearching)
            }
            .padding(16)

            if state.isSearching {
                ProgressView("Поиск")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LibrarySearchResultsView(library: library, state: state, onNavigateOut: onNavigateOut)
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
    }
}
```

- [ ] **Step 2: Add local search language picker**

In `LibrarySearchWindow.swift`, add this private picker below `LibrarySearchWindow`:

```swift
private struct SearchLanguagePicker: View {
    let library: Library
    @Binding var language: String

    var body: some View {
        Picker("", selection: $language) {
            ForEach(displayLanguages(), id: \.self) { code in
                Text(label(for: code)).tag(code)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func displayLanguages() -> [String] {
        var langs = library.languages
        langs.removeAll { $0.isEmpty }
        if library.languages.contains("") { langs.append(BooksByContext.unspecifiedLanguageToken) }
        return langs
    }

    private func label(for code: String) -> String {
        code == BooksByContext.unspecifiedLanguageToken ? "Не указан" : code.uppercased()
    }
}
```

Use it in the toolbar row:

```swift
SearchLanguagePicker(library: library, language: $s.language)
```

- [ ] **Step 3: Add grouped results view**

Create `FB Loader/FB Loader/UI/Search/LibrarySearchResultsView.swift`:

```swift
import SwiftUI

struct LibrarySearchResultsView: View {
    let library: Library
    let onNavigateOut: () -> Void
    @Environment(AppState.self) private var appState
    @Bindable var state: LibrarySearchWindowState

    var body: some View {
        VSplitView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(state.result.authors) { section in
                        sectionHeader(kind: "АВТОР", name: section.author.displayName,
                                      detail: "показано \(section.shown) из \(section.total)")
                        booksTable(section.books)
                    }
                    ForEach(state.result.series) { section in
                        sectionHeader(kind: "СЕРИЯ", name: section.series.name,
                                      detail: section.authorContext.isEmpty ? "показано \(section.shown) из \(section.total)" : "\(section.authorContext) · показано \(section.shown) из \(section.total)")
                        booksTable(section.books)
                    }
                    if !state.result.books.isEmpty {
                        sectionHeader(kind: "В ПОИСКЕ", name: "Совпадения по книгам",
                                      detail: "\(state.result.books.count) книг")
                        booksTable(state.result.books.map(\.book))
                    }
                }
            }
            selectedBookDetail
        }
    }

    private func sectionHeader(kind: String, name: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(kind).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text(name).font(.system(size: 15, weight: .semibold))
            Spacer()
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Color.black.opacity(0.035))
    }

    private func booksTable(_ books: [Book]) -> some View {
        VStack(spacing: 0) {
            ForEach(books, id: \.libid) { book in
                LibrarySearchBookRow(book: book, library: library,
                                     selected: state.selectedBookLibid == book.libid)
                    .onTapGesture { state.selectedBookLibid = book.libid }
            }
        }
    }

    @ViewBuilder
    private var selectedBookDetail: some View {
        if let libid = state.selectedBookLibid,
           let book = library.bookByLibid[libid],
           let archives = appState.userPaths.archivesDirectoryURL {
            BookDetailView(
                library: library,
                archivesRoot: archives,
                book: book,
                onLibraryNavigation: onNavigateOut
            )
                .frame(minHeight: 260)
        } else {
            Text("Выберите книгу")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 260)
        }
    }
}
```

- [ ] **Step 4: Add navigation callback to book detail**

Modify `FB Loader/FB Loader/UI/BookDetail/BookDetailView.swift`:

```swift
struct BookDetailView: View {
    let library: Library
    let archivesRoot: URL
    let book: Book
    var onLibraryNavigation: () -> Void = {}
```

In both author and series chip actions, call the callback after updating `AppState`:

```swift
Chip(title: author.displayName) {
    state.sidebarTab = .authors
    state.selectedAuthorID = aid
    state.selectedSeriesID = nil
    state.selectedGenreID = nil
    onLibraryNavigation()
}
```

```swift
Chip(title: seriesChipTitle(s)) {
    state.sidebarTab = .series
    state.selectedSeriesID = sid
    state.selectedAuthorID = nil
    state.selectedGenreID = nil
    onLibraryNavigation()
}
```

- [ ] **Step 5: Add search book row**

Append to `LibrarySearchResultsView.swift`:

```swift
private struct LibrarySearchBookRow: View {
    let book: Book
    let library: Library
    let selected: Bool
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var s = state
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { s.checkedBookLibids.contains(book.libid) },
                set: { isOn in
                    if isOn { s.checkedBookLibids.insert(book.libid) }
                    else { s.checkedBookLibids.remove(book.libid) }
                }))
                .toggleStyle(.compactCheckbox)
                .labelsHidden()
                .frame(width: 28)

            Text(book.title)
                .lineLimit(1)
                .fontWeight(selected ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(book.seriesNum.map(String.init) ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Text(ByteCountFormatter.string(fromByteCount: Int64(book.size), countStyle: .file))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(date(book.dateAdded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(book.genreIDs.prefix(3).compactMap { library.genreByID[$0]?.name }.joined(separator: ", "))
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 220, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: d)
    }
}
```

- [ ] **Step 6: Build UI**

Run:

```bash
xcodebuild build -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit search UI skeleton**

```bash
git add "FB Loader/FB Loader/UI/Search" "FB Loader/FB Loader/UI/BookDetail/BookDetailView.swift"
git commit -m "feat: add library search window UI"
```

---

### Task 4: Window Entry Points and Navigation

**Files:**
- Create: `FB Loader/FB Loader/UI/Search/LibrarySearchWindowController.swift`
- Modify: `FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift`
- Modify: `FB Loader/FB Loader/FB_LoaderApp.swift`

- [ ] **Step 1: Add search notification and opener**

Create `FB Loader/FB Loader/UI/Search/LibrarySearchWindowController.swift`:

```swift
import AppKit
import SwiftUI

extension Notification.Name {
    static let openLibrarySearch = Notification.Name("FBLoader.openLibrarySearch")
}

@MainActor
final class LibrarySearchWindowController {
    static let shared = LibrarySearchWindowController()
    private var window: NSWindow?
    private var cachedIndex: LibrarySearchIndex?

    func open(library: Library, appState: AppState) {
        let index = cachedIndex ?? LibrarySearchIndex(library: library)
        cachedIndex = index
        let service = LibrarySearchService(index: index, library: library)
        if let window {
            let root = LibrarySearchWindow(
                library: library,
                service: service,
                initialLanguage: appState.languageFilter,
                onNavigateOut: { [weak window] in window?.close() }
            )
            .environment(appState)
            window.contentView = NSHostingView(rootView: root)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let root = LibrarySearchWindow(
            library: library,
            service: service,
            initialLanguage: appState.languageFilter,
            onNavigateOut: { [weak window] in window?.close() }
        )
        .environment(appState)
        window.title = "FB Loader · Поиск по библиотеке"
        window.contentView = NSHostingView(rootView: root)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
```

- [ ] **Step 2: Listen for search notification in `ContentView`**

Modify `FB Loader/FB Loader/ContentView.swift` where it handles `.openSettings`. Add:

```swift
.onReceive(NotificationCenter.default.publisher(for: .openLibrarySearch)) { _ in
    if case .ready(let library) = state.stage {
        LibrarySearchWindowController.shared.open(library: library, appState: state)
    }
}
```

- [ ] **Step 3: Add sidebar search button**

Modify the top `HStack` in `FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift`:

```swift
Button {
    NotificationCenter.default.post(name: .openLibrarySearch, object: nil)
} label: {
    Image(systemName: "magnifyingglass")
}
.buttonStyle(.bordered)
.controlSize(.small)
.help("Поиск по библиотеке")
```

Keep the row order: segmented control, language picker, search button.

- [ ] **Step 4: Add Cmd+F command**

Modify `FB Loader/FB Loader/FB_LoaderApp.swift` inside `.commands`:

```swift
CommandGroup(after: .newItem) {
    Button("Поиск по библиотеке…") {
        NotificationCenter.default.post(name: .openLibrarySearch, object: nil)
    }
    .keyboardShortcut("f", modifiers: .command)
}
```

- [ ] **Step 5: Build entry points**

Run:

```bash
xcodebuild build -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit entry points**

```bash
git add "FB Loader/FB Loader/UI/Search/LibrarySearchWindowController.swift" "FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift" "FB Loader/FB Loader/ContentView.swift" "FB Loader/FB Loader/FB_LoaderApp.swift"
git commit -m "feat: wire library search window"
```

---

### Task 5: Integration Tests and Manual Verification

**Files:**
- Modify: `FB Loader/FB LoaderUITests/FB_LoaderUITests.swift`
- Modify: `docs/superpowers/specs/2026-05-04-library-search-design.md` only if implementation reveals a spec correction.

- [ ] **Step 1: Add UI smoke test for search entry**

Append to `FB Loader/FB LoaderUITests/FB_LoaderUITests.swift`:

```swift
func testLibrarySearchWindowOpensFromKeyboardShortcut() throws {
    let app = XCUIApplication()
    app.launch()

    app.typeKey("f", modifierFlags: [.command])

    let searchWindow = app.windows["FB Loader · Поиск по библиотеке"]
    XCTAssertTrue(searchWindow.waitForExistence(timeout: 5))
    XCTAssertTrue(searchWindow.textFields.firstMatch.exists)
    XCTAssertTrue(searchWindow.buttons["Поиск"].exists)
}
```

- [ ] **Step 2: Run UI smoke test**

Run:

```bash
xcodebuild test -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" -only-testing:FB_LoaderUITests/FB_LoaderUITests/testLibrarySearchWindowOpensFromKeyboardShortcut
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 3: Run all tests**

Run:

```bash
xcodebuild test -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS"
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Manual verification**

Launch the app and verify:

```text
1. Sidebar search button opens one separate search window.
2. Cmd+F opens the same search window.
3. Query "олди" with RU returns author, series, and book sections.
4. Query "сломаный меч" with RU returns direct book matches.
5. Changing language does not change the main sidebar language filter.
6. Checking a book in search updates the same checked state visible in the main table.
7. Clicking a book row opens the bottom detail area inside the search window.
8. Closing search leaves the main sidebar selection unchanged.
```

- [ ] **Step 5: Commit verification fixes**

If Step 3 or Step 4 required code changes, commit them:

```bash
git add "FB Loader/FB Loader" "FB Loader/FB LoaderTests" "FB Loader/FB LoaderUITests"
git commit -m "test: cover library search window"
```

If no code changes were needed, do not create an empty commit.

---

## Self-Review Checklist

- Spec coverage: entry point, separate window, language scope, grouped results, token scorer, no external fuzzy library, checkbox semantics, explicit navigation, and tests are covered.
- Type consistency: all search types use `LibrarySearch*` names and pass `Library`, `LibrarySearchIndex`, query, and language explicitly.
- State isolation: search owns query/results/detail; only checkboxes and explicit pills touch shared app state.
- No external package dependency is introduced.
- No placeholder tasks remain.
