# Sidebar Tab Selection — единая модель — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Перевести `AppState` сайдбара на единый `SidebarSelection` enum + развести три сценария мутации (Picker, deep-link с именем, клик в списке) с правильной семантикой сброса.

**Architecture:** Четыре независимых поля (`sidebarTab` + три `selectedXID`) схлопываются в `private(set) var sidebar: SidebarSelection` (enum с associated values). Picker и list-views получают custom Binding'и из `LeftSidebarView`; deep-link path из preview-chip получает имя через `library.authorByID`/`seriesByID` в `MainWindowView`. Список list-views, `FilteredSidebarList`, `LazyListTable`, `BookDetailView`, `ExportPlanner` — не меняются.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, Swift Testing, MainActor isolation.

---

## File Structure

- **Modify** `FB Loader/FB Loader/AppState.swift` — новый enum `SidebarSelection`, поле `sidebar`, четыре метода (`selectSection`, `selectAuthor`, `selectSeries`, `selectGenre`), апдейт `reset()`, удаление старых полей `sidebarTab`/`selectedAuthorID`/`selectedSeriesID`/`selectedGenreID` и старого `enum SidebarTab`.
- **Modify** `FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift` — Picker через custom Binding, мосты `Binding<Int32?>`/`Binding<Int16?>` для дочерних list-views.
- **Modify** `FB Loader/FB Loader/UI/MainWindowView.swift` — `onSelectAuthor`/`onSelectSeries` через `selectAuthor`/`selectSeries` с `deepLinkName`; `runExport` через pattern-match по `state.sidebar`.
- **Modify** `FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift` — `visibleBooks` и `breadcrumbLabel` на pattern-match.
- **Create** `FB Loader/FB LoaderTests/AppStateTests.swift` — Swift Testing suite по образцу `ExportProgressTests.swift`.

---

## Task 1: Добавить `SidebarSelection` и `sidebar` параллельно старым полям

Промежуточный шаг рефакторинга: модель добавляется, старые поля и call-site'ы продолжают работать, проект собирается. Это даёт чистую базу под TDD методов.

**Files:**
- Modify: `FB Loader/FB Loader/AppState.swift`

- [ ] **Step 1: Добавить enum и поле в AppState**

Открыть `AppState.swift`. Внутри тела `class AppState`, сразу после
`enum SidebarTab { case authors, series, genres }` (строка 21),
добавить вложенный enum и поле:

```swift
enum SidebarSelection: Equatable {
    case authors(Int32?)
    case series(Int32?)
    case genres(Int16?)
}

private(set) var sidebar: SidebarSelection = .authors(nil)
```

Оба объявления — внутри `AppState`. Тесты обращаются через
`s.sidebar == .authors(nil)`, тип выводится из контекста.

- [ ] **Step 2: Проверить сборку**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "FB Loader/FB Loader/AppState.swift"
git commit -m "feat(AppState): добавить SidebarSelection и поле sidebar"
```

---

## Task 2: Failing-тесты для нового API

Создать test suite. Все тесты обращаются к `state.sidebar` и методам, которых ещё нет → test target не скомпилируется (методы `selectSection/selectAuthor/selectSeries/selectGenre` отсутствуют).

**Files:**
- Create: `FB Loader/FB LoaderTests/AppStateTests.swift`

- [ ] **Step 1: Создать файл `FB Loader/FB LoaderTests/AppStateTests.swift`**

```swift
import Testing
@testable import FB_Loader

@Suite("AppStateTests")
@MainActor
struct AppStateTests {

    @Test("Дефолт: .authors(nil), пустые per-tab поля")
    func defaultState() {
        let s = AppState()
        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.languageFilter == "ru")
    }

    @Test("selectSection — смена case'а сбрасывает per-tab")
    func selectSectionSwitchesCase() {
        let s = AppState()
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.sidebarFilter = "abc"
        s.checkedBookLibids = [1, 2]
        s.languageFilter = "en"

        s.selectSection(.authors(nil))

        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.languageFilter == "en")
    }

    @Test("selectSection — точный no-op при равном sidebar")
    func selectSectionExactNoop() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7
        s.languageFilter = "en"

        s.selectSection(.authors(10))

        #expect(s.sidebar == .authors(10))
        #expect(s.sidebarFilter == "x")
        #expect(s.checkedBookLibids == [1])
        #expect(s.selectedBookLibid == 7)
        #expect(s.languageFilter == "en")
    }

    @Test("selectSection — same-case другой ID: полный сброс")
    func selectSectionSameCaseDifferentID() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectSection(.authors(nil))

        #expect(s.sidebar == .authors(nil))
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == nil)
    }

    @Test("selectAuthor без имени — same-case другой ID: гасит preview и галочки")
    func selectAuthorClickInList() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(42)

        #expect(s.sidebar == .authors(42))
        #expect(s.selectedBookLibid == nil)
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.sidebarFilter == "x")
    }

    @Test("selectAuthor без имени — same-ID no-op")
    func selectAuthorSameIDNoop() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(10)

        #expect(s.sidebar == .authors(10))
        #expect(s.selectedBookLibid == 7)
        #expect(s.checkedBookLibids == [1])
        #expect(s.sidebarFilter == "x")
    }

    @Test("selectAuthor с именем — cross-section: фильтр в имя, preview сохраняется")
    func selectAuthorDeepLinkCrossSection() {
        let s = AppState()
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.languageFilter = "en"

        s.selectAuthor(42, deepLinkName: "Иванов")

        #expect(s.sidebar == .authors(42))
        #expect(s.sidebarFilter == "Иванов")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
        #expect(s.languageFilter == "en")
    }

    @Test("selectAuthor с именем — same-section: фильтр перезаписан, preview сохранён")
    func selectAuthorDeepLinkSameSection() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "Толстой"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(42, deepLinkName: "Иванов")

        #expect(s.sidebar == .authors(42))
        #expect(s.sidebarFilter == "Иванов")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
    }

    @Test("selectAuthor с именем — same-ID re-click: идемпотентный прицел")
    func selectAuthorDeepLinkSameIDIdempotent() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "Толстой"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(10, deepLinkName: "Иванов")

        #expect(s.sidebar == .authors(10))
        #expect(s.sidebarFilter == "Иванов")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
    }

    @Test("selectSeries с именем — симметрично selectAuthor")
    func selectSeriesDeepLink() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectSeries(55, deepLinkName: "Ахейский цикл")

        #expect(s.sidebar == .series(55))
        #expect(s.sidebarFilter == "Ахейский цикл")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
    }

    @Test("selectGenre — без имени, как клик в списке")
    func selectGenreClickInList() {
        let s = AppState()
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.checkedBookLibids = [1]
        s.sidebarFilter = "x"

        s.selectGenre(7)

        #expect(s.sidebar == .genres(7))
        #expect(s.selectedBookLibid == nil)
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.sidebarFilter == "x")
    }

    @Test("selectAuthor(nil) внутри секции — same-section с nil ID")
    func selectAuthorNilInsideSection() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(nil)

        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.sidebarFilter == "x")
    }

    @Test("reset — sidebar=.authors(nil), все per-tab и language к дефолтам")
    func resetState() {
        let s = AppState()
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.languageFilter = "en"

        s.reset()

        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.languageFilter == "ru")
    }
}
```

- [ ] **Step 2: Проверить, что сборка тестов падает по unknown member**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build-for-testing -quiet`
Expected: BUILD FAILED — `'selectSection' is not a member of AppState`, `'selectAuthor'`, `'selectSeries'`, `'selectGenre'` отсутствуют.

- [ ] **Step 3: Commit failing tests**

```bash
git add "FB Loader/FB LoaderTests/AppStateTests.swift"
git commit -m "test(AppState): failing-тесты для нового API"
```

---

## Task 3: Реализовать все четыре метода и обновить `reset()`

Добавляем `selectSection`, `selectAuthor`, `selectSeries`, `selectGenre` (через приватный `applyEntitySelection`) и обновляем `reset()`. Все 13 тестов из Task 2 после этой таски должны проходить. Старые поля `sidebarTab`/`selectedXID` остаются в файле и обнуляются в `reset()` параллельно с новым `sidebar` — удалим их в Task 7.

**Files:**
- Modify: `FB Loader/FB Loader/AppState.swift`

- [ ] **Step 1: Добавить четыре метода в AppState**

Внутри класса `AppState`, после объявления `var checkedBookLibids: Set<Int32> = []` (примерно строка 29), добавить:

```swift
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
```

- [ ] **Step 2: Обновить `reset()`**

Заменить тело метода `reset()` целиком на:

```swift
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
```

Строки про старые поля (`sidebarTab`, `selectedXID`) остаются — они будут удалены в Task 7.

- [ ] **Step 3: Прогон тестов AppStateTests**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/AppStateTests" -quiet`

Expected: все 13 тестов AppStateTests — PASS.

- [ ] **Step 4: Commit**

```bash
git add "FB Loader/FB Loader/AppState.swift"
git commit -m "feat(AppState): SidebarSelection методы и reset()"
```

---

## Task 4: Перевести `LeftSidebarView` на новое API

Picker и Binding'и в дочерние list-views теперь идут через новый `sidebar` и методы. Старые поля `sidebarTab`/`selectedXID` в AppState всё ещё существуют, но `LeftSidebarView` к ним больше не обращается.

**Files:**
- Modify: `FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift`

- [ ] **Step 1: Заменить тело `body`**

Открыть `LeftSidebarView.swift`. В функции `body` (строки 9–71) заменить блок:

```swift
HStack(spacing: 8) {
    Picker("", selection: $s.sidebarTab) {
        Text("Авторы").tag(AppState.SidebarTab.authors)
        Text("Серии").tag(AppState.SidebarTab.series)
        Text("Жанры").tag(AppState.SidebarTab.genres)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
```

на (вытаскиваем helper-Binding и helper-метку):

```swift
HStack(spacing: 8) {
    Picker("", selection: pickerBinding) {
        Text("Авторы").tag(SectionTag.authors)
        Text("Серии").tag(SectionTag.series)
        Text("Жанры").tag(SectionTag.genres)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
```

Внутри `switch s.sidebarTab` (строки 44–60) заменить на:

```swift
switch state.sidebar {
case .authors(let id):
    AuthorsListView(library: library,
                    filterText: s.sidebarFilter,
                    languageFilter: s.languageFilter,
                    selectedAuthorID: authorBinding(currentID: id))
case .series(let id):
    SeriesListView(library: library,
                   filterText: s.sidebarFilter,
                   languageFilter: s.languageFilter,
                   selectedSeriesID: seriesBinding(currentID: id))
case .genres(let id):
    GenresListView(library: library,
                   filterText: s.sidebarFilter,
                   languageFilter: s.languageFilter,
                   selectedGenreID: genreBinding(currentID: id))
}
```

- [ ] **Step 2: Добавить SectionTag, pickerBinding и Binding-хелперы**

В конец `struct LeftSidebarView`, перед закрывающей скобкой и перед `private func searchSheetSize()`, добавить:

```swift
private enum SectionTag: Hashable { case authors, series, genres }

private var pickerBinding: Binding<SectionTag> {
    Binding(
        get: {
            switch state.sidebar {
            case .authors: return .authors
            case .series:  return .series
            case .genres:  return .genres
            }
        },
        set: { newTag in
            switch newTag {
            case .authors: state.selectSection(.authors(nil))
            case .series:  state.selectSection(.series(nil))
            case .genres:  state.selectSection(.genres(nil))
            }
        }
    )
}

private func authorBinding(currentID: Int32?) -> Binding<Int32?> {
    Binding(get: { currentID }, set: { state.selectAuthor($0) })
}

private func seriesBinding(currentID: Int32?) -> Binding<Int32?> {
    Binding(get: { currentID }, set: { state.selectSeries($0) })
}

private func genreBinding(currentID: Int16?) -> Binding<Int16?> {
    Binding(get: { currentID }, set: { state.selectGenre($0) })
}
```

- [ ] **Step 3: Сборка**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Прогон тестов**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -quiet`
Expected: все тесты — PASS.

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift"
git commit -m "refactor(LeftSidebarView): Picker и list-views через SidebarSelection"
```

---

## Task 5: Перевести `MainWindowView` на новое API

`onSelectAuthor`/`onSelectSeries` теперь зовут `selectAuthor`/`selectSeries` с именем из `library`. `runExport` достаёт ID через pattern-match по `state.sidebar`.

**Files:**
- Modify: `FB Loader/FB Loader/UI/MainWindowView.swift`

- [ ] **Step 1: Заменить closure'ы `onSelectAuthor` / `onSelectSeries`**

В `body` `MainWindowView` (строки 31–42) заменить:

```swift
onSelectAuthor: { aid in
    state.sidebarTab = .authors
    state.selectedAuthorID = aid
    state.selectedSeriesID = nil
    state.selectedGenreID = nil
},
onSelectSeries: { sid in
    state.sidebarTab = .series
    state.selectedSeriesID = sid
    state.selectedAuthorID = nil
    state.selectedGenreID = nil
}
```

на:

```swift
onSelectAuthor: { aid in
    let name = library.authorByID[aid]?.displayName
    state.selectAuthor(aid, deepLinkName: name)
},
onSelectSeries: { sid in
    let name = library.seriesByID[sid]?.name
    state.selectSeries(sid, deepLinkName: name)
}
```

- [ ] **Step 2: Заменить аргументы в `runExport`**

В функции `runExport` (строки 94–132) заменить:

```swift
let items = ExportPlanner.plan(
    libids: state.checkedBookLibids,
    rootFolder: folder,
    selectedAuthorID: state.sidebarTab == .authors ? state.selectedAuthorID : nil,
    selectedSeriesID: state.sidebarTab == .series ? state.selectedSeriesID : nil,
    in: library)
```

на:

```swift
let authorID: Int32?
if case .authors(let id) = state.sidebar { authorID = id } else { authorID = nil }
let seriesID: Int32?
if case .series(let id) = state.sidebar { seriesID = id } else { seriesID = nil }
let items = ExportPlanner.plan(
    libids: state.checkedBookLibids,
    rootFolder: folder,
    selectedAuthorID: authorID,
    selectedSeriesID: seriesID,
    in: library)
```

- [ ] **Step 3: Сборка**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Прогон тестов**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -quiet`
Expected: все тесты — PASS.

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/UI/MainWindowView.swift"
git commit -m "refactor(MainWindowView): deep-link и runExport через SidebarSelection"
```

---

## Task 6: Перевести `BooksTableView` на pattern-match

`visibleBooks` и `breadcrumbLabel` читают `state.sidebar` через pattern-match.

**Files:**
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift`

- [ ] **Step 1: Переписать `visibleBooks`**

Заменить тело `visibleBooks` (строки 18–35):

```swift
private var visibleBooks: [Book] {
    if let aid = state.selectedAuthorID, state.sidebarTab == .authors {
        return BooksByContext.books(for: .author(aid),
                                    language: state.languageFilter,
                                    in: library)
    }
    if let sid = state.selectedSeriesID, state.sidebarTab == .series {
        return BooksByContext.books(for: .series(sid),
                                    language: state.languageFilter,
                                    in: library)
    }
    if let gid = state.selectedGenreID, state.sidebarTab == .genres {
        return BooksByContext.books(for: .genre(gid),
                                    language: state.languageFilter,
                                    in: library)
    }
    return []
}
```

на:

```swift
private var visibleBooks: [Book] {
    switch state.sidebar {
    case .authors(let id?):
        return BooksByContext.books(for: .author(id),
                                    language: state.languageFilter,
                                    in: library)
    case .series(let id?):
        return BooksByContext.books(for: .series(id),
                                    language: state.languageFilter,
                                    in: library)
    case .genres(let id?):
        return BooksByContext.books(for: .genre(id),
                                    language: state.languageFilter,
                                    in: library)
    case .authors, .series, .genres:
        return []
    }
}
```

- [ ] **Step 2: Переписать `breadcrumbLabel`**

Заменить тело `breadcrumbLabel` (строки 148–165):

```swift
private var breadcrumbLabel: (prefix: String, name: String)? {
    if state.sidebarTab == .authors,
       let aid = state.selectedAuthorID,
       let author = library.authorByID[aid] {
        return ("Книги автора", author.displayName)
    }
    if state.sidebarTab == .series,
       let sid = state.selectedSeriesID,
       let series = library.seriesByID[sid] {
        return ("Серия", series.name)
    }
    if state.sidebarTab == .genres,
       let gid = state.selectedGenreID,
       let genre = library.genreByID[gid] {
        return ("Жанр", genre.name)
    }
    return nil
}
```

на:

```swift
private var breadcrumbLabel: (prefix: String, name: String)? {
    switch state.sidebar {
    case .authors(let id?):
        guard let author = library.authorByID[id] else { return nil }
        return ("Книги автора", author.displayName)
    case .series(let id?):
        guard let series = library.seriesByID[id] else { return nil }
        return ("Серия", series.name)
    case .genres(let id?):
        guard let genre = library.genreByID[id] else { return nil }
        return ("Жанр", genre.name)
    case .authors, .series, .genres:
        return nil
    }
}
```

- [ ] **Step 3: Сборка**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Прогон тестов**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -quiet`
Expected: все тесты — PASS.

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift"
git commit -m "refactor(BooksTableView): pattern-match по SidebarSelection"
```

---

## Task 7: Удалить старые поля из `AppState`

Все call-site'ы переведены на новый API. Удаляем `enum SidebarTab`, `var sidebarTab`, `var selectedAuthorID`, `var selectedSeriesID`, `var selectedGenreID` и упоминания в `reset()`.

**Files:**
- Modify: `FB Loader/FB Loader/AppState.swift`

- [ ] **Step 1: Удалить старые объявления**

В `AppState.swift` удалить строки:

```swift
enum SidebarTab { case authors, series, genres }
var sidebarTab: SidebarTab = .authors
var selectedAuthorID: Int32? = nil
var selectedSeriesID: Int32? = nil
var selectedGenreID: Int16? = nil
```

- [ ] **Step 2: Почистить `reset()`**

В `reset()` удалить строки:

```swift
sidebarTab = .authors
selectedAuthorID = nil
selectedSeriesID = nil
selectedGenreID = nil
```

Должно остаться:

```swift
func reset() {
    sidebar = .authors(nil)
    selectedBookLibid = nil
    languageFilter = "ru"
    sidebarFilter = ""
    checkedBookLibids.removeAll()
}
```

- [ ] **Step 3: Сборка**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build -quiet`
Expected: BUILD SUCCEEDED. Если падает с «'sidebarTab' is not a member» или подобным — какой-то call-site не был переведён в задачах 4–6; найти и поправить, прежде чем продолжать.

- [ ] **Step 4: Прогон всех тестов**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -quiet`
Expected: все тесты — PASS.

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/AppState.swift"
git commit -m "refactor(AppState): удалить старые поля сайдбара"
```

---

## Task 8: Ручная UI-проверка

Запускает Алексей. Проверяет пять сценариев из спеки. По правилу из CLAUDE.md → «UI-таски ждут ручной проверки перед коммитом» — но все коммиты уже сделаны в TDD-цикле; здесь проверка финальная, без новых коммитов.

- [ ] **Step 1: Запустить приложение из Xcode**

Открыть `FB Loader/FB Loader.xcodeproj` в Xcode, ⌘R.

- [ ] **Step 2: Проверка бага**

Серии → выбрать серию → выбрать книгу → переключить Picker на Авторы.
Ожидание: фильтр пуст, в списке авторов ничего не выделено, средняя панель пуста («Выберите автора, серию или жанр»), preview гасится.

- [ ] **Step 3: Скролл-позиция**

Авторы → проскроллить вниз → Picker на Серии → Picker обратно на Авторы.
Ожидание: список авторов начинается с верха.

- [ ] **Step 4: Deep-link same-section**

В табе Авторы выбрать автора с соавтором (например, «Олди Генри Лайон»). Кликнуть на книге → в preview chip соавтора.
Ожидание: Picker остаётся на Авторах. Фильтр сайдбара = имя соавтора. В списке соавтор подсвечен и виден. Preview той же книги сохранён. В средней панели книга подсвечена среди книг соавтора.

- [ ] **Step 5: Deep-link cross-section**

В табе Авторы кликнуть на книге из серии → в preview chip серии.
Ожидание: Picker переключается на Серии. Фильтр сайдбара = имя серии. В списке серия подсвечена и видна. Preview сохранён. В средней панели книга подсвечена среди книг серии.

- [ ] **Step 6: Клик в списке сайдбара**

В табе Авторы выбрать автора A → выбрать книгу автора A → в списке сайдбара кликнуть автора B.
Ожидание: preview гасится. Фильтр сайдбара сохраняется. Галочки (если были) сбрасываются.

- [ ] **Step 7: Сообщить Алексею результат**

Если все пять сценариев работают — план завершён. Если что-то не так — остановиться, не пушить, сообщить.

---

## Final

После одобрения Алексея на ручной проверке — план закрыт. **Мерж и пуш — только по явному «мержи» / «пуш» от Алексея (CLAUDE.md → пункты 15, 16).**
