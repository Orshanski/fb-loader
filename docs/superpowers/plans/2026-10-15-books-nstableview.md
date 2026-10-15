# Таблица книг на NSTableView — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** заменить таблицу книг главного окна (`ScrollView` + `LazyVStack`) на `NSTableView` через `NSViewRepresentable` с клавиатурой, фокусом, Tab и VoiceOver, сохранив вид.

**Architecture:** чистая модель строк `BookTableRows` (nonisolated) → `BooksTableRepresentable` + `Coordinator` (data source, delegate, выбор без петель, поповер даты) → AppKit-классы в `BooksNSTableView.swift` (таблица, шапка, строка, ячейки, галочка). SwiftUI-строка заголовка со счётчиком остаётся над `NSScrollView`. `body` строит строки и ключ; выбор и галочки читает только `updateNSView`.

**Tech Stack:** Swift 6, SwiftUI + AppKit (`NSTableView`, `NSTableHeaderView`, `NSPopover`), Swift Testing, macOS 14.

**Spec:** `docs/superpowers/specs/2026-10-15-books-nstableview-design.md` (коммит b1a8723). Исполнитель читает спеку и план.

## Global Constraints

- Ветка `feature/books-nstableview`, работа в основной папке репозитория, без `git worktree`. Коммит после каждой задачи. Ни push, ни merge.
- Префикс путей кода — `FB Loader/FB Loader/`, тестов — `FB Loader/FB LoaderTests/`. Новые `.swift` попадают в target сами (`PBXFileSystemSynchronizedRootGroup`), `project.pbxproj` не трогать.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Чистые типы — `nonisolated` + `Sendable`. AppKit-классы и координатор — MainActor (по умолчанию). Тесты с AppKit — `@MainActor`.
- Тесты — Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), не XCTest. TDD: тест → красный → код → зелёный.
- Поиск по символам — LSP (`findReferences`, `goToDefinition`), grep — только для текста.
- Комментарии — только неочевидное «почему», одна строка, по-русски.
- Не менять: `UI/Search/*`, `BookRow.swift` (кроме doc-комментария в задаче 9), `CompactCheckbox.swift`, ключ окружения `bookTableColumns`, `AppState`, `DateFilterPopover`, `MonthCalendar`, `BookDetailView`, сайдбар. `BooksByContext` — только `Context: Equatable`.
- В ячейках нет `NSHostingView`.
- Строки дословно: «Выгрузить отмеченные (N)», «Отметить: <название>», «—», «?», «Название», «№», «Размер», «Дата», «Жанры».
- Вывод сборки не обрезать `tail`/`head` (блокирует хук), фильтровать `grep`. Три предупреждения `appintentsmetadataprocessor … Metadata extraction skipped` — шум; остальные предупреждения чинить.
- Ошибка `CodeSign failed … FB LoaderTests.xctest … is not signed` — заменить `test` на `clean test` в команде и прогнать снова.
- Приложение не запускать; ручная проверка — Alexey (список в конце).

**Команда прогона тестов** (вся задача использует её; «зелёный» = в выводе есть `** TEST SUCCEEDED **` и нет строк `error:`, `warning:`, `failed`, `recorded an issue`):

```bash
cd /Users/alexey/code/fb-loader && xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" -derivedDataPath ~/Library/Developer/Xcode/DerivedData/FBLoader-agent test > /private/tmp/claude-501/-Users-alexey-code-fb-loader/5425557b-e8c8-461a-a36d-79f0ff20700c/scratchpad/agent-build.log 2>&1; grep -E "error:|warning:|\*\* TEST|failed|recorded an issue" /private/tmp/claude-501/-Users-alexey-code-fb-loader/5425557b-e8c8-461a-a36d-79f0ff20700c/scratchpad/agent-build.log | grep -v "Metadata extraction skipped"
```

«Красный» на шаге проверки падения — `error:` компиляции (нет типа/метода) или `recorded an issue` / `** TEST FAILED **`.

## Review Focus

1. Повторный клик по «Дате» при открытом transient-поповере: поповер закрывается кликом вне, и тот же `mouseDown` не должен открыть его снова → тест `datePress` в задаче 7.
2. ⇧↓ на таблице с одиночным выбором: `NSTableView` может предложить `{текущая, заголовок}`; выбор должен уйти на книгу за заголовком → `arrowsSkipHeader` в задаче 6, выбор «не текущей» из предложения — `proposedSelection` в задаче 5.
3. Полосы прокрутки «всегда»: ширины колонок считаются от ширины clip view, сумма = ширине clip view, подписи над значениями → тест `layoutColumns` в задаче 5.
4. ПКМ по невыделенной книге: меню есть, выделение и модель не меняются → тест `menu(for:)` в задаче 6.
5. Hover после `reloadData` не остаётся на строке с чужим индексом → `hoverResetsOnReload` в задаче 6.

---

### Task 1: Модель строк — порядок и индекс

**Files:**
- Create: `FB Loader/FB Loader/UI/BooksTable/BookTableRows.swift`
- Test: `FB Loader/FB LoaderTests/BookTableRowsTests.swift`

**Interfaces:**
- Consumes: `Book`, `Series`, `Library.series(id:)` (существуют).
- Produces:
  ```swift
  nonisolated enum BookTableRow: Sendable { case book(Book, inSeries: Bool); case seriesHeader(Series, count: Int) }
  nonisolated struct BookTableRows: Sendable {
      let rows: [BookTableRow]
      init(rows: [BookTableRow])
      static let empty: BookTableRows
      var count: Int
      func row(ofLibid libid: Int32) -> Int?
      func isBook(_ row: Int) -> Bool
      func libid(at row: Int) -> Int32?
      func book(at row: Int) -> Book?
      static func build(books: [Book], library: Library) -> BookTableRows
  }
  ```

Правило порядка: сверху книги без серии в порядке выборки; затем серии по имени (`<` на `String`), одинаковые имена — по id серии; неизвестная серия (`library.series(id:) == nil`) — `Series(id: sid, name: "?")`; внутри серии по `seriesNum`, без номера — в конце; одинаковые номера и книги без номера — в порядке выборки. `count` заголовка — книг серии в выборке. Индекс по libid строится в `init`, при дубле — первая строка.

- [ ] **Step 1: Тесты**

```swift
import Testing
import Foundation
@testable import FB_Loader

@Suite("BookTableRows")
struct BookTableRowsTests {
    private func book(_ libid: Int32, series: Int32? = nil, num: Int16? = nil) -> Book {
        Book(libid: libid, title: "B\(libid)", authorIDs: [1], seriesID: series, seriesNum: num,
             genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAdded: nil)
    }

    private func library(_ series: [Series]) -> Library {
        Library(inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
                authors: [Author(id: 1, lastName: "X", firstName: "", middleName: "")],
                series: series, genres: [], books: [])
    }

    /// Книга вне серии — «libid», книга серии — «  libid», заголовок — «[имя count]».
    private func describe(_ r: BookTableRows) -> [String] {
        r.rows.map {
            switch $0 {
            case .book(let b, let inSeries): return inSeries ? "  \(b.libid)" : "\(b.libid)"
            case .seriesHeader(let s, let count): return "[\(s.name) \(count)]"
            }
        }
    }

    @Test("без серий — книги в порядке выборки, без заголовков")
    func noSeries() {
        let r = BookTableRows.build(books: [book(3), book(1), book(2)], library: library([]))
        #expect(describe(r) == ["3", "1", "2"])
    }

    @Test("книги без серии выше всех серий, count — книг серии в выборке")
    func looseFirst() {
        let lib = library([Series(id: 1, name: "Альфа")])
        let r = BookTableRows.build(
            books: [book(10, series: 1, num: 1), book(20), book(11, series: 1, num: 2), book(21)],
            library: lib)
        #expect(describe(r) == ["20", "21", "[Альфа 2]", "  10", "  11"])
    }

    @Test("серии по имени, одинаковые имена — по id, неизвестная — «?»")
    func seriesOrder() {
        let lib = library([Series(id: 2, name: "Б"), Series(id: 3, name: "А"), Series(id: 1, name: "А")])
        let r = BookTableRows.build(
            books: [book(1, series: 2), book(2, series: 3), book(3, series: 1), book(4, series: 9)],
            library: lib)
        #expect(describe(r) == ["[? 1]", "  4", "[А 1]", "  3", "[А 1]", "  2", "[Б 1]", "  1"])
    }

    @Test("внутри серии по номеру, без номера — в конце в порядке выборки")
    func seriesNumbers() {
        let lib = library([Series(id: 1, name: "S")])
        let r = BookTableRows.build(
            books: [book(1, series: 1, num: 3), book(2, series: 1), book(3, series: 1, num: 1),
                    book(4, series: 1), book(5, series: 1, num: 2)],
            library: lib)
        #expect(describe(r) == ["[S 5]", "  3", "  5", "  1", "  2", "  4"])
    }

    @Test("row(ofLibid:), isBook, libid(at:), book(at:)")
    func lookup() {
        let lib = library([Series(id: 1, name: "Альфа")])
        let r = BookTableRows.build(
            books: [book(10, series: 1, num: 1), book(20), book(11, series: 1, num: 2)],
            library: lib)
        // 0: 20, 1: [Альфа 2], 2: 10, 3: 11
        #expect(r.row(ofLibid: 20) == 0)
        #expect(r.row(ofLibid: 11) == 3)
        #expect(r.row(ofLibid: 99) == nil)
        #expect(r.isBook(0))
        #expect(!r.isBook(1))
        #expect(!r.isBook(-1))
        #expect(!r.isBook(4))
        #expect(r.libid(at: 1) == nil)
        #expect(r.libid(at: 2) == 10)
        #expect(r.book(at: 99) == nil)
        #expect(r.count == 4)
    }

    @Test("дубль libid — индекс на первую строку")
    func duplicateLibid() {
        let b = book(1)
        let r = BookTableRows(rows: [.book(b, inSeries: false), .book(b, inSeries: true)])
        #expect(r.row(ofLibid: 1) == 0)
    }

    @Test("пустая выборка — пустые строки")
    func empty() {
        let r = BookTableRows.build(books: [], library: library([]))
        #expect(r.rows.isEmpty)
        #expect(r.count == 0)
        #expect(BookTableRows.empty.count == 0)
    }
}
```

- [ ] **Step 2: Прогон — красный** (команда из «Global Constraints»). Ожидается `error: cannot find 'BookTableRows' in scope`.

- [ ] **Step 3: Реализация**

```swift
import Foundation

nonisolated enum BookTableRow: Sendable {
    case book(Book, inSeries: Bool)
    case seriesHeader(Series, count: Int)
}

/// Строки таблицы книг главного окна: книги без серии, затем группы серий.
nonisolated struct BookTableRows: Sendable {
    let rows: [BookTableRow]
    private let rowByLibid: [Int32: Int]

    init(rows: [BookTableRow]) {
        self.rows = rows
        var index: [Int32: Int] = [:]
        index.reserveCapacity(rows.count)
        for (i, row) in rows.enumerated() {
            if case .book(let b, _) = row, index[b.libid] == nil { index[b.libid] = i }
        }
        rowByLibid = index
    }

    static let empty = BookTableRows(rows: [])

    var count: Int { rows.count }

    func row(ofLibid libid: Int32) -> Int? { rowByLibid[libid] }

    func book(at row: Int) -> Book? {
        guard rows.indices.contains(row), case .book(let b, _) = rows[row] else { return nil }
        return b
    }

    func isBook(_ row: Int) -> Bool { book(at: row) != nil }

    func libid(at row: Int) -> Int32? { book(at: row)?.libid }

    static func build(books: [Book], library: Library) -> BookTableRows {
        var result: [BookTableRow] = []
        result.reserveCapacity(books.count)
        var bySeries: [Int32: [(offset: Int, book: Book)]] = [:]
        for (offset, b) in books.enumerated() {
            if let sid = b.seriesID {
                bySeries[sid, default: []].append((offset, b))
            } else {
                result.append(.book(b, inSeries: false))
            }
        }
        let series = bySeries.keys
            .map { library.series(id: $0) ?? Series(id: $0, name: "?") }
            .sorted { $0.name != $1.name ? $0.name < $1.name : $0.id < $1.id }
        for s in series {
            let items = (bySeries[s.id] ?? []).sorted { a, b in
                let na = a.book.seriesNum ?? .max
                let nb = b.book.seriesNum ?? .max
                return na != nb ? na < nb : a.offset < b.offset
            }
            result.append(.seriesHeader(s, count: items.count))
            result.append(contentsOf: items.map { .book($0.book, inSeries: true) })
        }
        return BookTableRows(rows: result)
    }
}
```

- [ ] **Step 4: Прогон — зелёный.**

- [ ] **Step 5: Коммит**

```bash
cd /Users/alexey/code/fb-loader && git add "FB Loader/FB Loader/UI/BooksTable/BookTableRows.swift" "FB Loader/FB LoaderTests/BookTableRowsTests.swift" && git commit -m "feat(books-table): модель строк таблицы книг

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Разрешение выбора, цель прокрутки, маршрут пробела

**Files:**
- Modify: `FB Loader/FB Loader/UI/BooksTable/BookTableRows.swift`
- Test: `FB Loader/FB LoaderTests/BookTableRowsTests.swift` (дописать), `FB Loader/FB LoaderTests/SpaceRouteTests.swift` (новый)

**Interfaces:**
- Consumes: `BookTableRows` из задачи 1.
- Produces:
  ```swift
  extension BookTableRows {
      func resolveSelection(proposed: Int?, current: Int?, byKeyboard: Bool) -> Int?
      enum ScrollTarget: Equatable, Sendable { case top; case row(Int, header: Int?) }
      func scrollTarget(selectedLibid: Int32?) -> ScrollTarget
  }
  nonisolated enum SpaceRoute: Equatable, Sendable { case toggleCheck, typeSelect }
  nonisolated func spaceRoute(lastTypeSelectKey: Date?, now: Date) -> SpaceRoute
  ```

Правила `resolveSelection`: предложение `nil` или вне строк → `current`; книга → она; заголовок мышью → `current`; заголовок клавиатурой → ближайшая книга по направлению от `current` (вниз, если `proposed > current` или `current == nil`; иначе вверх); такой книги нет → `current`.
`scrollTarget`: выбранной нет или её нет в строках → `.top`; книга → `.row(r, header: r - 1)`, если строка `r - 1` — заголовок, иначе `header: nil`.
`spaceRoute`: нет буквы → `.toggleCheck`; прошло меньше 1 с → `.typeSelect`; 1 с и больше → `.toggleCheck`.

- [ ] **Step 1: Тесты** — дописать в `BookTableRowsTests` (внутрь struct):

```swift
    /// 0: книга 1, 1: [S], 2: книга 2, 3: книга 3, 4: [T], 5: книга 4.
    private var rowsA: BookTableRows {
        BookTableRows(rows: [
            .book(book(1), inSeries: false),
            .seriesHeader(Series(id: 1, name: "S"), count: 2),
            .book(book(2, series: 1), inSeries: true),
            .book(book(3, series: 1), inSeries: true),
            .seriesHeader(Series(id: 2, name: "T"), count: 1),
            .book(book(4, series: 2), inSeries: true),
        ])
    }

    /// 0: [S], 1: книга 1, 2: книга 2.
    private var rowsB: BookTableRows {
        BookTableRows(rows: [
            .seriesHeader(Series(id: 1, name: "S"), count: 2),
            .book(book(1, series: 1), inSeries: true),
            .book(book(2, series: 1), inSeries: true),
        ])
    }

    @Test("клавиатура: заголовок ниже текущей — следующая книга, выше — предыдущая")
    func keyboardSkipsHeader() {
        #expect(rowsA.resolveSelection(proposed: 4, current: 3, byKeyboard: true) == 5)
        #expect(rowsA.resolveSelection(proposed: 4, current: 5, byKeyboard: true) == 3)
    }

    @Test("клавиатура: заголовок в строке 0 без текущей — строка 1; ↑ на первой книге — текущая")
    func keyboardEdges() {
        #expect(rowsB.resolveSelection(proposed: 0, current: nil, byKeyboard: true) == 1)
        #expect(rowsB.resolveSelection(proposed: 0, current: 1, byKeyboard: true) == 1)
    }

    @Test("мышь на заголовке — текущая; пустое — текущая; книга — книга")
    func mouseAndEmpty() {
        #expect(rowsA.resolveSelection(proposed: 1, current: 3, byKeyboard: false) == 3)
        #expect(rowsA.resolveSelection(proposed: 1, current: nil, byKeyboard: false) == nil)
        #expect(rowsA.resolveSelection(proposed: nil, current: 2, byKeyboard: false) == 2)
        #expect(rowsA.resolveSelection(proposed: nil, current: 2, byKeyboard: true) == 2)
        #expect(rowsA.resolveSelection(proposed: 5, current: 0, byKeyboard: false) == 5)
        #expect(rowsA.resolveSelection(proposed: 5, current: 0, byKeyboard: true) == 5)
        #expect(rowsA.resolveSelection(proposed: 99, current: 0, byKeyboard: true) == 0)
    }

    @Test("scrollTarget: нет выбранной или нет в строках — к началу; книга — строка и заголовок серии")
    func scrollTargets() {
        #expect(rowsA.scrollTarget(selectedLibid: nil) == .top)
        #expect(rowsA.scrollTarget(selectedLibid: 99) == .top)
        #expect(rowsA.scrollTarget(selectedLibid: 1) == .row(0, header: nil))
        #expect(rowsA.scrollTarget(selectedLibid: 2) == .row(2, header: 1))
        #expect(rowsA.scrollTarget(selectedLibid: 3) == .row(3, header: nil))
        #expect(rowsB.scrollTarget(selectedLibid: 1) == .row(1, header: 0))
    }
```

`SpaceRouteTests.swift`:

```swift
import Testing
import Foundation
@testable import FB_Loader

@Suite("SpaceRoute")
struct SpaceRouteTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    @Test("без type-select — галочка")
    func noTypeSelect() {
        #expect(spaceRoute(lastTypeSelectKey: nil, now: t0) == .toggleCheck)
    }

    @Test("0,5 с после буквы — поиск")
    func withinWindow() {
        #expect(spaceRoute(lastTypeSelectKey: t0, now: t0 + 0.5) == .typeSelect)
        #expect(spaceRoute(lastTypeSelectKey: t0, now: t0 + 0.999) == .typeSelect)
    }

    @Test("1,0 с и позже — галочка")
    func afterWindow() {
        #expect(spaceRoute(lastTypeSelectKey: t0, now: t0 + 1.0) == .toggleCheck)
        #expect(spaceRoute(lastTypeSelectKey: t0, now: t0 + 5) == .toggleCheck)
    }
}
```

- [ ] **Step 2: Прогон — красный** (`value of type 'BookTableRows' has no member 'resolveSelection'`, `cannot find 'spaceRoute'`).

- [ ] **Step 3: Реализация** — дописать в `BookTableRows.swift`:

```swift
extension BookTableRows {
    /// Заголовок серии не выбирается: клавиатура перескакивает его по
    /// направлению движения, мышь оставляет прежний выбор.
    func resolveSelection(proposed: Int?, current: Int?, byKeyboard: Bool) -> Int? {
        guard let p = proposed, rows.indices.contains(p) else { return current }
        if isBook(p) { return p }
        guard byKeyboard else { return current }
        let downward = current.map { p > $0 } ?? true
        if downward {
            return (p + 1 ..< rows.count).first(where: isBook) ?? current
        }
        return (0 ..< p).reversed().first(where: isBook) ?? current
    }

    enum ScrollTarget: Equatable, Sendable {
        case top
        case row(Int, header: Int?)
    }

    func scrollTarget(selectedLibid: Int32?) -> ScrollTarget {
        guard let libid = selectedLibid, let r = row(ofLibid: libid) else { return .top }
        let header = r > 0 && !isBook(r - 1) ? r - 1 : nil
        return .row(r, header: header)
    }
}

nonisolated enum SpaceRoute: Equatable, Sendable {
    case toggleCheck, typeSelect
}

/// Пробел внутри набора type-select («Война и мир») — часть поиска, а не галочка.
nonisolated func spaceRoute(lastTypeSelectKey: Date?, now: Date) -> SpaceRoute {
    guard let last = lastTypeSelectKey else { return .toggleCheck }
    return now.timeIntervalSince(last) < 1 ? .typeSelect : .toggleCheck
}
```

- [ ] **Step 4: Прогон — зелёный.**

- [ ] **Step 5: Коммит**

```bash
cd /Users/alexey/code/fb-loader && git add "FB Loader/FB Loader/UI/BooksTable/BookTableRows.swift" "FB Loader/FB LoaderTests/BookTableRowsTests.swift" "FB Loader/FB LoaderTests/SpaceRouteTests.swift" && git commit -m "feat(books-table): разрешение выбора, цель прокрутки, маршрут пробела

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Раскладка колонок NSTableView

**Files:**
- Modify: `FB Loader/FB Loader/UI/BooksTable/BookTableColumns.swift`
- Test: `FB Loader/FB LoaderTests/BookTableColumnsTests.swift` (дописать)

**Interfaces:**
- Consumes: `BookTableColumns.visibleColumns(forWidth:)` (существует, не менять).
- Produces:
  ```swift
  extension BookTableColumns { static let rowInset: CGFloat /* 16 */; static func columnLayout(forWidth: CGFloat) -> BookTableColumnLayout }
  nonisolated enum BookTableColumnID: String, CaseIterable, Sendable { case title, num, size, date, genres; var headerTitle: String }
  nonisolated struct BookTableColumnLayout: Equatable, Sendable {
      let title: CGFloat; let num: CGFloat; let size: CGFloat?; let date: CGFloat; let genres: CGFloat?
      func width(of: BookTableColumnID) -> CGFloat?   // nil — колонка скрыта
      var totalWidth: CGFloat
  }
  ```

`intercellSpacing = 0`, поэтому промежутки и отступы — внутри ширин колонок:
- `title` = остаток = 16 + 28 + 10 + ширина названия;
- `num` = 10 + 50; `size` = 10 + 80 (или скрыта); `date` = 10 + 100; `genres` = 10 + `genresWidth` (или скрыта);
- последняя видимая (`genres`, а без неё `date`) + 16 справа;
- сумма = ширине. «Дата» видна всегда. Видимость — из `visibleColumns(forWidth:)`.

- [ ] **Step 1: Тесты** — дописать в `BookTableColumnsTests` (внутрь struct):

```swift
    @Test("columnLayout: сумма ширин = ширине, Дата видна, последняя колонка содержит 16 справа",
          arguments: [CGFloat(1400), 640, 639, 510, 509, BookTableColumns.minimumPaneWidth])
    func columnLayoutSums(width: CGFloat) {
        let l = C.columnLayout(forWidth: width)
        let v = C.visibleColumns(forWidth: width)
        #expect(l.totalWidth == width)
        #expect(l.num == C.spacing + C.numWidth)
        #expect((l.size != nil) == v.showsSize)
        #expect((l.genres != nil) == v.showsGenres)
        if let genres = l.genres {
            #expect(genres == C.spacing + v.genresWidth + C.rowInset)
            #expect(l.date == C.spacing + C.dateWidth)
        } else {
            #expect(l.date == C.spacing + C.dateWidth + C.rowInset)
        }
        #expect(l.title >= C.rowInset + C.checkboxWidth + C.spacing + C.titleMinWidth)
        #expect(l.width(of: .date) == l.date)
        #expect(l.width(of: .size) == l.size)
        #expect(l.width(of: .genres) == l.genres)
    }

    @Test("заголовки колонок")
    func headerTitles() {
        #expect(BookTableColumnID.allCases.map(\.headerTitle) == ["Название", "№", "Размер", "Дата", "Жанры"])
    }
```

- [ ] **Step 2: Прогон — красный** (`type 'BookTableColumns' has no member 'columnLayout'`).

- [ ] **Step 3: Реализация** — дописать в `BookTableColumns.swift` (существующий код не менять):

```swift
nonisolated enum BookTableColumnID: String, CaseIterable, Sendable {
    case title, num, size, date, genres

    var headerTitle: String {
        switch self {
        case .title: "Название"
        case .num: "№"
        case .size: "Размер"
        case .date: "Дата"
        case .genres: "Жанры"
        }
    }
}

nonisolated struct BookTableColumnLayout: Equatable, Sendable {
    let title: CGFloat
    let num: CGFloat
    let size: CGFloat?
    let date: CGFloat
    let genres: CGFloat?

    func width(of column: BookTableColumnID) -> CGFloat? {
        switch column {
        case .title: title
        case .num: num
        case .size: size
        case .date: date
        case .genres: genres
        }
    }

    var totalWidth: CGFloat { title + num + (size ?? 0) + date + (genres ?? 0) }
}

extension BookTableColumns {
    static let rowInset: CGFloat = 16

    /// Ширины колонок NSTableView при `intercellSpacing = 0`: промежуток 10
    /// входит в колонку слева, отступ строки 16 — в первую и последнюю.
    static func columnLayout(forWidth width: CGFloat) -> BookTableColumnLayout {
        let v = visibleColumns(forWidth: width)
        let num = spacing + numWidth
        let size: CGFloat? = v.showsSize ? spacing + sizeWidth : nil
        let genres: CGFloat? = v.showsGenres ? spacing + v.genresWidth + rowInset : nil
        let date = spacing + dateWidth + (genres == nil ? rowInset : 0)
        let title = width - num - (size ?? 0) - date - (genres ?? 0)
        return BookTableColumnLayout(title: title, num: num, size: size, date: date, genres: genres)
    }
}
```

- [ ] **Step 4: Прогон — зелёный.**

- [ ] **Step 5: Коммит**

```bash
cd /Users/alexey/code/fb-loader && git add "FB Loader/FB Loader/UI/BooksTable/BookTableColumns.swift" "FB Loader/FB LoaderTests/BookTableColumnsTests.swift" && git commit -m "feat(books-table): раскладка колонок NSTableView

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Ячейки, галочка, строка

**Files:**
- Create: `FB Loader/FB Loader/UI/BooksTable/BooksNSTableView.swift`
- Test: `FB Loader/FB LoaderTests/BooksTableCellsTests.swift`

**Interfaces:**
- Consumes: `BookTableColumns.rowInset/checkboxWidth/spacing/indent/numWidth/sizeWidth/dateWidth`, `BookTableColumnID` (задача 3).
- Produces:
  ```swift
  extension BookTableColumnID { var identifier: NSUserInterfaceItemIdentifier }
  final class BookCheckbox: NSControl { var isOn: Bool; var isEmphasized: Bool; var onToggle: (() -> Void)? }
  final class BookTitleCellView: NSTableCellView {
      let checkbox: BookCheckbox; let titleLabel: NSTextField
      private(set) var leadingInset: CGFloat; private(set) var showsSelected: Bool
      func configure(book: Book, inSeries: Bool, isChecked: Bool, isSelected: Bool, onToggle: @escaping () -> Void)
  }
  final class BookTextCellView: NSTableCellView { init(column: BookTableColumnID); let column: BookTableColumnID; let label: NSTextField; func configure(text: String) }
  final class SeriesHeaderCellView: NSTableCellView { let nameLabel: NSTextField; let countLabel: NSTextField; func configure(series: Series, count: Int) }
  final class BooksRowView: NSTableRowView { var isHovered: Bool }
  ```

Вид (из спеки):
- Галочка 14×14, скругление 3, рамка 1pt внутри. Обычная строка и серое выделение: выкл — заливка белая, рамка `white 0.78`; вкл — заливка и рамка `controlAccentColor`, белая `checkmark` 9pt bold. Строка с `backgroundStyle == .emphasized` (акцентное выделение с фокусом): выкл — прозрачная заливка, белая рамка; вкл — белая заливка, галочка `controlAccentColor`.
- Галочка: `refusesFirstResponder = true`, `acceptsFirstResponder == false`, переключение на `mouseUp` внутри (`mouseDown` поглощается), VoiceOver: роль `checkBox`, метка «Отметить: <название>», значение 0/1, `accessibilityPerformPress` переключает.
- Ячейка `title`: галочка в 28pt-ячейке по центру (левый край галочки = inset + 7), название с inset + 28 + 10, inset = 16 (книга вне серии) или 30 (в серии; `rowInset + indent`). Название 13pt, `.semibold` у выбранной, `labelColor`, одна строка, усечение хвоста. `textField = titleLabel` — тогда `NSTableCellView` сам передаёт `backgroundStyle` полю (белый текст на акцентном выделении).
- Ячейки `num/size/date`: поле с 10 слева, фиксированной ширины 50/80/100, по правому краю, `monospacedDigitSystemFont(13)`, `secondaryLabelColor`. `genres`: с 10 слева до 16 справа, по левому краю, `systemFont(13)`, `secondaryLabelColor`, усечение хвоста. Лишние 16 справа у последней колонки «Дата» остаются пустыми — ячейке не нужно знать, последняя ли она.
- Заголовок серии: имя 13pt semibold (усечение хвоста, сжимается первым) + `(N)` 12pt `secondaryLabelColor` (не сжимается), промежуток 4, выравнивание по первой базовой линии; 16 слева, `(N)` не дальше 16 от правого края; низ имени — 4 от низа строки (строка 32 = 12 + 16 + 4).
- Строка: hover — заливка `black 3%` на всю строку только у книг (не у групповой строки) и не у выделенной; групповая строка не рисует системный фон.

- [ ] **Step 1: Тесты** — `BooksTableCellsTests.swift`:

```swift
import AppKit
import Testing
@testable import FB_Loader

@Suite("BooksTable cells")
@MainActor
struct BooksTableCellsTests {
    private func book(_ title: String) -> Book {
        Book(libid: 7, title: title, authorIDs: [1], seriesID: nil, seriesNum: nil,
             genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAdded: nil)
    }

    @Test("галочка: не берёт фокус, роль checkbox, нажатие VoiceOver переключает")
    func checkbox() {
        let box = BookCheckbox()
        var toggles = 0
        box.onToggle = { toggles += 1 }
        #expect(box.refusesFirstResponder)
        #expect(!box.acceptsFirstResponder)
        #expect(box.accessibilityRole() == .checkBox)
        #expect(box.accessibilityValue() as? NSNumber == 0)
        box.isOn = true
        #expect(box.accessibilityValue() as? NSNumber == 1)
        #expect(box.accessibilityPerformPress())
        #expect(toggles == 1)
    }

    @Test("ячейка названия: отступ 16 вне серии и 30 в серии, выбранная — жирная, метка галочки")
    func titleCell() {
        let cell = BookTitleCellView()
        cell.configure(book: book("Война и мир"), inSeries: false, isChecked: true, isSelected: false, onToggle: {})
        #expect(cell.leadingInset == 16)
        #expect(!cell.showsSelected)
        #expect(cell.checkbox.isOn)
        #expect(cell.titleLabel.stringValue == "Война и мир")
        #expect(cell.textField === cell.titleLabel)
        #expect(cell.checkbox.accessibilityLabel() == "Отметить: Война и мир")

        cell.configure(book: book("Б"), inSeries: true, isChecked: false, isSelected: true, onToggle: {})
        #expect(cell.leadingInset == 30)
        #expect(cell.showsSelected)
        #expect(!cell.checkbox.isOn)
    }

    @Test("акцентное выделение переключает вид галочки")
    func emphasized() {
        let cell = BookTitleCellView()
        cell.backgroundStyle = .emphasized
        #expect(cell.checkbox.isEmphasized)
        cell.backgroundStyle = .normal
        #expect(!cell.checkbox.isEmphasized)
    }

    @Test("ячейки чисел — по правому краю, жанры — по левому")
    func textCells() {
        for id in [BookTableColumnID.num, .size, .date] {
            let cell = BookTextCellView(column: id)
            #expect(cell.label.alignment == .right)
            #expect(cell.textField === cell.label)
        }
        let genres = BookTextCellView(column: .genres)
        #expect(genres.label.alignment == .left)
        genres.configure(text: "Фантастика, Детектив")
        #expect(genres.label.stringValue == "Фантастика, Детектив")
    }

    @Test("заголовок серии: имя и (N)")
    func seriesHeader() {
        let cell = SeriesHeaderCellView()
        cell.configure(series: Series(id: 1, name: "Дюна"), count: 3)
        #expect(cell.nameLabel.stringValue == "Дюна")
        #expect(cell.countLabel.stringValue == "(3)")
    }

    @Test("идентификаторы колонок")
    func identifiers() {
        #expect(BookTableColumnID.title.identifier.rawValue == "title")
        #expect(BookTableColumnID.genres.identifier.rawValue == "genres")
    }
}
```

- [ ] **Step 2: Прогон — красный** (`cannot find 'BookCheckbox' in scope`).

- [ ] **Step 3: Реализация** — `BooksNSTableView.swift`:

```swift
import AppKit

extension BookTableColumnID {
    var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }
}

private func makeLabel() -> NSTextField {
    let f = NSTextField(labelWithString: "")
    f.translatesAutoresizingMaskIntoConstraints = false
    f.lineBreakMode = .byTruncatingTail
    f.cell?.usesSingleLineMode = true
    f.cell?.truncatesLastVisibleLine = true
    return f
}

/// Своё `NSControl`, а не `NSButton`: вид — 14×14 из CompactCheckbox, а клик
/// не должен ни выделять строку, ни брать фокус.
final class BookCheckbox: NSControl {
    var isOn = false { didSet { if isOn != oldValue { needsDisplay = true } } }
    var isEmphasized = false { didSet { if isEmphasized != oldValue { needsDisplay = true } } }
    var onToggle: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        refusesFirstResponder = true
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 14, height: 14) }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onToggle?() }
    }

    override func accessibilityValue() -> Any? { NSNumber(value: isOn ? 1 : 0) }

    override func accessibilityPerformPress() -> Bool {
        guard let onToggle else { return false }
        onToggle()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: (bounds.width - 14) / 2, y: (bounds.height - 14) / 2, width: 14, height: 14)
        let fill: NSColor
        let stroke: NSColor
        let tick: NSColor
        switch (isEmphasized, isOn) {
        case (false, false): fill = .white; stroke = NSColor(white: 0.78, alpha: 1); tick = .clear
        case (false, true): fill = .controlAccentColor; stroke = .controlAccentColor; tick = .white
        case (true, false): fill = .clear; stroke = .white; tick = .clear
        case (true, true): fill = .white; stroke = .white; tick = .controlAccentColor
        }
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
        path.lineWidth = 1
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.stroke()
        guard isOn,
              let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [tick])))
        else { return }
        let s = image.size
        image.draw(in: NSRect(x: box.midX - s.width / 2, y: box.midY - s.height / 2,
                              width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// Галочка живёт в ячейке названия: только так отступ книги серии сдвигает
/// галочку и название вместе, а правые колонки стоят на месте.
final class BookTitleCellView: NSTableCellView {
    let checkbox = BookCheckbox()
    let titleLabel = makeLabel()
    private(set) var leadingInset: CGFloat = BookTableColumns.rowInset
    private(set) var showsSelected = false
    private var checkboxLeading: NSLayoutConstraint!
    private var labelLeading: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .labelColor
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(checkbox)
        addSubview(titleLabel)
        textField = titleLabel
        checkboxLeading = checkbox.leadingAnchor.constraint(equalTo: leadingAnchor)
        labelLeading = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            checkboxLeading, labelLeading,
            checkbox.widthAnchor.constraint(equalToConstant: 14),
            checkbox.heightAnchor.constraint(equalToConstant: 14),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyInset()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { checkbox.isEmphasized = backgroundStyle == .emphasized }
    }

    func configure(book: Book, inSeries: Bool, isChecked: Bool, isSelected: Bool,
                   onToggle: @escaping () -> Void) {
        leadingInset = BookTableColumns.rowInset + (inSeries ? BookTableColumns.indent : 0)
        applyInset()
        showsSelected = isSelected
        titleLabel.stringValue = book.title
        titleLabel.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular)
        checkbox.isOn = isChecked
        checkbox.onToggle = onToggle
        checkbox.setAccessibilityLabel("Отметить: \(book.title)")
    }

    private func applyInset() {
        checkboxLeading.constant = leadingInset + (BookTableColumns.checkboxWidth - 14) / 2
        labelLeading.constant = leadingInset + BookTableColumns.checkboxWidth + BookTableColumns.spacing
    }
}

final class BookTextCellView: NSTableCellView {
    let column: BookTableColumnID
    let label = makeLabel()

    init(column: BookTableColumnID) {
        precondition(column != .title, "Название рисует BookTitleCellView")
        self.column = column
        super.init(frame: .zero)
        identifier = column.identifier
        label.textColor = .secondaryLabelColor
        label.alignment = column == .genres ? .left : .right
        label.font = column == .genres
            ? .systemFont(ofSize: 13)
            : .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        textField = label
        var constraints = [
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: BookTableColumns.spacing),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        switch column {
        case .num: constraints.append(label.widthAnchor.constraint(equalToConstant: BookTableColumns.numWidth))
        case .size: constraints.append(label.widthAnchor.constraint(equalToConstant: BookTableColumns.sizeWidth))
        case .date: constraints.append(label.widthAnchor.constraint(equalToConstant: BookTableColumns.dateWidth))
        case .genres: constraints.append(label.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                                         constant: -BookTableColumns.rowInset))
        case .title: break
        }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(text: String) { label.stringValue = text }
}

final class SeriesHeaderCellView: NSTableCellView {
    let nameLabel = makeLabel()
    let countLabel = makeLabel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = .labelColor
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(nameLabel)
        addSubview(countLabel)
        textField = nameLabel
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: BookTableColumns.rowInset),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            countLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            countLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                                 constant: -BookTableColumns.rowInset),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(series: Series, count: Int) {
        nameLabel.stringValue = series.name
        countLabel.stringValue = "(\(count))"
    }
}

final class BooksRowView: NSTableRowView {
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    override func drawBackground(in dirtyRect: NSRect) {
        // Групповая строка — заголовок серии: без системного фона и без hover.
        guard !isGroupRowStyle else { return }
        super.drawBackground(in: dirtyRect)
        if isHovered && !isSelected {
            NSColor.black.withAlphaComponent(0.03).setFill()
            bounds.fill()
        }
    }
}
```

- [ ] **Step 4: Прогон — зелёный.**

- [ ] **Step 5: Коммит**

```bash
cd /Users/alexey/code/fb-loader && git add "FB Loader/FB Loader/UI/BooksTable/BooksNSTableView.swift" "FB Loader/FB LoaderTests/BooksTableCellsTests.swift" && git commit -m "feat(books-table): ячейки, галочка и строка NSTableView

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Таблица и координатор — данные, выбор без петель, колонки

**Files:**
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksByContext.swift:12` — `enum Context: Equatable { … }`
- Modify: `FB Loader/FB Loader/UI/BooksTable/BookTableRows.swift` — `BooksTableKey`
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksNSTableView.swift` — класс `BooksNSTableView`
- Create: `FB Loader/FB Loader/UI/BooksTable/BooksTableRepresentable.swift`
- Test: `FB Loader/FB LoaderTests/BooksTableCoordinatorTests.swift`

**Interfaces:**
- Consumes: всё из задач 1–4; `ExportAction` (`UI/BooksTable/BooksTableView.swift:5`, `final class` с `var perform: () -> Void`); `AppState.selectedBookLibid/checkedBookLibids/dateFilter/applyDateFilter(_:)`; `DateFormat.dayMonthYear`.
- Produces:
  ```swift
  nonisolated struct BooksTableKey: Equatable, Sendable { let context: BooksByContext.Context?; let language: String; let dates: DateRangeFilter? }
  @MainActor protocol BooksTableModel: AnyObject {
      var selectedBookLibid: Int32? { get set }; var checkedBookLibids: Set<Int32> { get set }
      var dateFilter: DateRangeFilter? { get }; func applyDateFilter(_ next: DateRangeFilter?)
  }
  extension AppState: BooksTableModel {}
  final class BooksNSTableView: NSTableView {
      static let bookRowHeight: CGFloat /* 24 */; static let seriesHeaderHeight: CGFloat /* 32 */
      private(set) var isHandlingKeyDown: Bool; private(set) var reloadDataCount: Int
  }
  struct BooksTableRepresentable: NSViewRepresentable {
      let state: AppState; let library: Library; let rows: BookTableRows; let key: BooksTableKey; let exportAction: ExportAction
      static func makeScrollView(coordinator: Coordinator) -> NSScrollView
      final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
          init(model: any BooksTableModel, library: Library, exportAction: ExportAction)
          var model: any BooksTableModel; var library: Library; var exportAction: ExportAction
          private(set) var rows: BookTableRows; private(set) var key: BooksTableKey?
          private(set) weak var tableView: BooksNSTableView?
          func attach(table: BooksNSTableView, scrollView: NSScrollView)
          func apply(rows: BookTableRows, key: BooksTableKey, selectedLibid: Int32?, checked: Set<Int32>)
          func layoutColumns(width: CGFloat)
          func withoutWritingSelection(_ body: () -> Void)
          func syncSelection(of tableView: NSTableView, to libid: Int32?)
          func toggleCheck(libid: Int32)
          func cellText(for book: Book, column: BookTableColumnID) -> String
      }
  }
  ```
  `FakeBooksTableModel`, `BooksTableFixture`, `BooksTableHarness` в тестовом файле — их используют задачи 6 и 7.

Правила (из спеки, всё переносится в код):
- Флаги таблицы: `style = .plain`, `columnAutoresizingStyle = .noColumnAutoresizing`, `allowsColumnResizing = false`, `allowsColumnReordering = false`, `allowsColumnSelection = false`, `allowsMultipleSelection = false`, `allowsEmptySelection = true`, `usesAutomaticRowHeights = false`, `floatsGroupRows = false`, `gridStyleMask = []`, `selectionHighlightStyle = .regular`, `intercellSpacing = .zero`, `backgroundColor = .clear`. Scroll view: `hasVerticalScroller = true`, `hasHorizontalScroller = false`, `drawsBackground = false`, `borderType = .noBorder`, `automaticallyAdjustsContentInsets = false`, `contentInsets.bottom = 4`.
- Колонки: идентификаторы `title/num/size/date/genres`, `resizingMask = []`, `minWidth = 0`, `maxWidth = .greatestFiniteMagnitude`. Ширины и `isHidden` — `layoutColumns(width:)` по `columnLayout(forWidth:)` от ширины clip view, вызывается из `NSView.frameDidChangeNotification` clip view (`postsFrameChangedNotifications = true`). Без `reloadData()`.
- Заголовок серии — `isGroupRow == true` (единственная ячейка на всю ширину, `viewFor` с `tableColumn == nil`), не липнет (`floatsGroupRows = false`). Высоты — `heightOfRow`: книга 24, заголовок 32.
- `apply`: `reloadData()` только при смене ключа или `rows.count`; порядок: `reloadData` (под `withoutWritingSelection`) → `syncSelection` → прокрутка по `scrollTarget` (`scrollRowToVisible(header)`, затем `(row)`; `.top` — `scrollRowToVisible(0)`, если строки есть) → `headerView?.needsDisplay = true`. Иначе — `syncSelection` и, если сменились выбор или галочки, `reloadData(forRowIndexes: видимые, columnIndexes: колонка title)`.
- `syncSelection` — под `withoutWritingSelection`; выбранной книги нет в строках — `deselectAll` молча.
- `tableViewSelectionDidChange`: пишет `model.selectedBookLibid` строки книги, если не поднят флаг; при `selectedRow == -1` или заголовке не пишет; если строка выше — заголовок, `scrollRowToVisible(row - 1)`.
- `tableView(_:selectionIndexesForProposedSelection:)` → `resolveSelection`; `byKeyboard = (tableView as? BooksNSTableView)?.isHandlingKeyDown`. Из предложения берётся индекс, отличный от текущей строки (⇧↓ может предложить `{текущая, следующая}`), иначе первый.
- `typeSelectStringFor` — название книги, у заголовка `nil`.
- `validateProposedFirstResponder(_:for:)` подкласса — `true` для `BookCheckbox`: клик по галочке не выделяет строку.
- Галочка переключается через `toggleCheck(libid:)`, `selectedBookLibid` не пишется.
- Тексты ячеек: `num` — `seriesNum` или «—»; `size` — `ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)`; `date` — `DateFormat.dayMonthYear` или «—»; `genres` — имена из `library.genreByID` через «, ».

- [ ] **Step 1: Тесты** — `BooksTableCoordinatorTests.swift`:

```swift
import AppKit
import Testing
@testable import FB_Loader

@MainActor
final class FakeBooksTableModel: BooksTableModel {
    var selectionWrites: [Int32?] = []
    var selectedBookLibid: Int32? = nil { didSet { selectionWrites.append(selectedBookLibid) } }
    var checkedBookLibids: Set<Int32> = []
    private(set) var dateFilter: DateRangeFilter? = nil
    private(set) var appliedFilters: [DateRangeFilter?] = []
    func applyDateFilter(_ next: DateRangeFilter?) {
        appliedFilters.append(next)
        dateFilter = next
    }
}

@MainActor
enum BooksTableFixture {
    static func book(_ libid: Int32, _ title: String, series: Int32? = nil, num: Int16? = nil,
                     genres: [Int16] = []) -> Book {
        Book(libid: libid, title: title, authorIDs: [1], seriesID: series, seriesNum: num,
             genreIDs: genres, language: "ru", archiveIndex: 0, size: 2048, dateAdded: nil)
    }

    static let library = Library(
        inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
        authors: [Author(id: 1, lastName: "X", firstName: "", middleName: "")],
        series: [Series(id: 1, name: "Серия")],
        genres: [Genre(id: 1, code: "sf", name: "Фантастика", parentID: nil),
                 Genre(id: 2, code: "det", name: "Детектив", parentID: nil)],
        books: [])

    /// Строки: 0 «Альфа» (10), 1 «Бета» (11), 2 [Серия 2], 3 «Гамма» (20, №1), 4 «Дельта» (21, №2).
    static let books: [Book] = [
        book(10, "Альфа", genres: [1, 2]), book(11, "Бета"),
        book(20, "Гамма", series: 1, num: 1), book(21, "Дельта", series: 1, num: 2),
    ]
}

/// Таблица в окне (не показанном): клавиатура, `visibleRect` и `row(at:)` работают как в приложении.
@MainActor
final class BooksTableHarness {
    let model = FakeBooksTableModel()
    let exportAction = ExportAction()
    let coordinator: BooksTableRepresentable.Coordinator
    let scrollView: NSScrollView
    let window: NSWindow
    var table: BooksNSTableView { coordinator.tableView! }

    init(books: [Book] = BooksTableFixture.books, context: BooksByContext.Context? = .author(1),
         dates: DateRangeFilter? = nil, selected: Int32? = nil, checked: Set<Int32> = []) {
        model.selectedBookLibid = selected
        model.checkedBookLibids = checked
        coordinator = BooksTableRepresentable.Coordinator(
            model: model, library: BooksTableFixture.library, exportAction: exportAction)
        scrollView = BooksTableRepresentable.makeScrollView(coordinator: coordinator)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                          styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        apply(books: books, context: context, dates: dates)
        model.selectionWrites.removeAll()
    }

    func apply(books: [Book], context: BooksByContext.Context?, dates: DateRangeFilter? = nil) {
        coordinator.apply(rows: BookTableRows.build(books: books, library: BooksTableFixture.library),
                          key: BooksTableKey(context: context, language: "ru", dates: dates),
                          selectedLibid: model.selectedBookLibid, checked: model.checkedBookLibids)
    }

    func select(row: Int) {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    func titleCell(row: Int) -> BookTitleCellView? {
        coordinator.tableView(table, viewFor: table.tableColumn(withIdentifier: BookTableColumnID.title.identifier),
                              row: row) as? BookTitleCellView
    }
}

@Suite("BooksTable coordinator")
@MainActor
struct BooksTableCoordinatorTests {
    @Test("выбор строки книги пользователем пишет libid; два шага — две записи")
    func userSelectionWrites() {
        let h = BooksTableHarness()
        h.select(row: 0)
        h.select(row: 3)
        #expect(h.model.selectionWrites == [10, 20])
    }

    @Test("syncSelection к книге выделяет строку, к отсутствующей снимает; в модель не пишет")
    func syncDoesNotWrite() {
        let h = BooksTableHarness()
        h.coordinator.syncSelection(of: h.table, to: 21)
        #expect(h.table.selectedRow == 4)
        h.coordinator.syncSelection(of: h.table, to: 99)
        #expect(h.table.selectedRow == -1)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("новый ключ без выбранной книги в строках — не пишет, выделения нет")
    func newKeyWithoutSelected() {
        let h = BooksTableHarness(selected: 10)
        #expect(h.table.selectedRow == 0)
        h.apply(books: [BooksTableFixture.books[1]], context: .author(2))
        #expect(h.table.selectedRow == -1)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("deep-link: новый ключ, выбранная книга есть — строка выделена, не пишет")
    func deepLinkSelects() {
        let h = BooksTableHarness(books: [BooksTableFixture.books[0]])
        h.model.selectedBookLibid = 21
        h.model.selectionWrites.removeAll()
        h.apply(books: BooksTableFixture.books, context: .series(1))
        #expect(h.table.selectedRow == 4)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("снятие выделения (selectedRow == -1) не пишет")
    func deselectDoesNotWrite() {
        let h = BooksTableHarness()
        h.select(row: 0)
        h.model.selectionWrites.removeAll()
        h.table.deselectAll(nil)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("тот же ключ и rows.count — reloadData() не вызывается; новый ключ — вызывается")
    func reloadOnlyOnKeyChange() {
        let h = BooksTableHarness()
        let before = h.table.reloadDataCount
        h.model.checkedBookLibids = [10]
        h.model.selectedBookLibid = 11
        h.apply(books: BooksTableFixture.books, context: .author(1))
        #expect(h.table.reloadDataCount == before)
        h.apply(books: BooksTableFixture.books, context: .author(2))
        #expect(h.table.reloadDataCount == before + 1)
    }

    @Test("предложение выбора: мышь на заголовке — текущая; пусто — текущая; книга — книга; из двух — не текущая")
    func proposedSelection() {
        let h = BooksTableHarness()
        let c = h.coordinator
        #expect(c.tableView(h.table, selectionIndexesForProposedSelection: IndexSet(integer: 2)) == IndexSet())
        h.select(row: 1)
        #expect(c.tableView(h.table, selectionIndexesForProposedSelection: IndexSet(integer: 2)) == IndexSet(integer: 1))
        #expect(c.tableView(h.table, selectionIndexesForProposedSelection: IndexSet()) == IndexSet(integer: 1))
        #expect(c.tableView(h.table, selectionIndexesForProposedSelection: IndexSet(integer: 4)) == IndexSet(integer: 4))
        // Из {текущая, другая} берётся не текущая.
        #expect(c.tableView(h.table, selectionIndexesForProposedSelection: IndexSet([1, 3])) == IndexSet(integer: 3))
    }

    @Test("заголовок серии — групповая строка 32pt, книга — 24pt")
    func groupRows() {
        let h = BooksTableHarness()
        #expect(h.coordinator.tableView(h.table, isGroupRow: 2))
        #expect(!h.coordinator.tableView(h.table, isGroupRow: 0))
        #expect(h.coordinator.tableView(h.table, heightOfRow: 2) == 32)
        #expect(h.coordinator.tableView(h.table, heightOfRow: 3) == 24)
        #expect(h.coordinator.tableView(h.table, typeSelectStringFor: nil, row: 2) == nil)
        #expect(h.coordinator.tableView(h.table, typeSelectStringFor: nil, row: 3) == "Гамма")
    }

    @Test("колонки по ширине clip view: сумма = ширине, Жанры и Размер скрываются, Дата видна")
    func layoutColumns() {
        let h = BooksTableHarness()
        func visibleSum() -> CGFloat {
            h.table.tableColumns.filter { !$0.isHidden }.reduce(0) { $0 + $1.width }
        }
        func hidden(_ id: BookTableColumnID) -> Bool {
            h.table.tableColumn(withIdentifier: id.identifier)!.isHidden
        }
        h.coordinator.layoutColumns(width: 1200)
        #expect(visibleSum() == 1200)
        #expect(!hidden(.genres))
        h.coordinator.layoutColumns(width: 600)
        #expect(visibleSum() == 600)
        #expect(hidden(.genres))
        #expect(!hidden(.size))
        h.coordinator.layoutColumns(width: 500)
        #expect(visibleSum() == 500)
        #expect(hidden(.size))
        #expect(!hidden(.date))
    }

    @Test("тексты ячеек: «—» без номера и даты, жанры через запятую, размер файла")
    func cellTexts() {
        let c = BooksTableHarness().coordinator
        let alpha = BooksTableFixture.books[0]
        #expect(c.cellText(for: alpha, column: .num) == "—")
        #expect(c.cellText(for: alpha, column: .date) == "—")
        #expect(c.cellText(for: alpha, column: .genres) == "Фантастика, Детектив")
        #expect(c.cellText(for: alpha, column: .size)
                == ByteCountFormatter.string(fromByteCount: 2048, countStyle: .file))
        #expect(c.cellText(for: BooksTableFixture.books[2], column: .num) == "1")
    }

    @Test("ячейка названия: галочка, жирность выбранной, метка доступности")
    func titleCellState() {
        let h = BooksTableHarness(selected: 10, checked: [11])
        #expect(h.titleCell(row: 0)?.showsSelected == true)
        #expect(h.titleCell(row: 1)?.showsSelected == false)
        #expect(h.titleCell(row: 1)?.checkbox.isOn == true)
        #expect(h.titleCell(row: 0)?.checkbox.accessibilityLabel() == "Отметить: Альфа")
        #expect(h.titleCell(row: 3)?.leadingInset == 30)
    }

    @Test("переключение галочки через координатор не пишет selectedBookLibid")
    func toggleDoesNotSelect() {
        let h = BooksTableHarness()
        #expect(h.titleCell(row: 1)?.checkbox.accessibilityPerformPress() == true)
        #expect(h.model.checkedBookLibids == [11])
        h.coordinator.toggleCheck(libid: 11)
        #expect(h.model.checkedBookLibids.isEmpty)
        #expect(h.model.selectionWrites.isEmpty)
        #expect(h.table.selectedRow == -1)
    }

    @Test("клик по галочке не выделяет строку: таблица отдаёт событие галочке")
    func checkboxGetsMouse() {
        let h = BooksTableHarness()
        let box = BookCheckbox()
        #expect(h.table.validateProposedFirstResponder(box, for: nil))
    }
}
```

- [ ] **Step 2: Прогон — красный** (`cannot find type 'BooksTableModel'`, `cannot find 'BooksTableRepresentable'`).

- [ ] **Step 3a: `BooksByContext.swift`** — строка 12: `enum Context: Equatable { case author(Int32), series(Int32), genre(Int16) }`.

- [ ] **Step 3b: `BookTableRows.swift`** — дописать:

```swift
/// Смена ключа — новая выборка: перезагрузка строк, прокрутка, перерисовка шапки.
nonisolated struct BooksTableKey: Equatable, Sendable {
    let context: BooksByContext.Context?
    let language: String
    let dates: DateRangeFilter?
}
```

- [ ] **Step 3c: `BooksNSTableView.swift`** — дописать класс таблицы (задача 6 расширит `keyDown`):

```swift
final class BooksNSTableView: NSTableView {
    static let bookRowHeight: CGFloat = 24
    static let seriesHeaderHeight: CGFloat = 32

    /// Поднят на время `super.keyDown`: заголовок серии, предложенный стрелкой,
    /// перескакивается, а предложенный мышью — нет.
    private(set) var isHandlingKeyDown = false
    private(set) var reloadDataCount = 0

    override func reloadData() {
        reloadDataCount += 1
        super.reloadData()
    }

    override func keyDown(with event: NSEvent) {
        isHandlingKeyDown = true
        defer { isHandlingKeyDown = false }
        super.keyDown(with: event)
    }

    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is BookCheckbox { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }
}
```

- [ ] **Step 3d: `BooksTableRepresentable.swift`**:

```swift
import SwiftUI
import AppKit

/// Координатор пишет выбор и галочки через протокол: в тестах — подделка,
/// считающая записи.
@MainActor
protocol BooksTableModel: AnyObject {
    var selectedBookLibid: Int32? { get set }
    var checkedBookLibids: Set<Int32> { get set }
    var dateFilter: DateRangeFilter? { get }
    func applyDateFilter(_ next: DateRangeFilter?)
}

extension AppState: BooksTableModel {}

struct BooksTableRepresentable: NSViewRepresentable {
    let state: AppState
    let library: Library
    let rows: BookTableRows
    let key: BooksTableKey
    let exportAction: ExportAction

    func makeCoordinator() -> Coordinator {
        Coordinator(model: state, library: library, exportAction: exportAction)
    }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(coordinator: context.coordinator)
    }

    func updateNSView(_: NSScrollView, context: Context) {
        let c = context.coordinator
        c.model = state
        c.library = library
        c.exportAction = exportAction
        // Выбор и галочки читаются здесь, а не в body: их смена перезапускает
        // только updateNSView, выборка не пересчитывается.
        c.apply(rows: rows, key: key,
                selectedLibid: state.selectedBookLibid, checked: state.checkedBookLibids)
    }

    static func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let table = BooksNSTableView()
        table.style = .plain
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnResizing = false
        table.allowsColumnReordering = false
        table.allowsColumnSelection = false
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.usesAutomaticRowHeights = false
        table.floatsGroupRows = false
        table.gridStyleMask = []
        table.selectionHighlightStyle = .regular
        table.intercellSpacing = .zero
        table.rowHeight = BooksNSTableView.bookRowHeight
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        for id in BookTableColumnID.allCases {
            let column = NSTableColumn(identifier: id.identifier)
            column.title = id.headerTitle
            column.resizingMask = []
            column.minWidth = 0
            column.maxWidth = .greatestFiniteMagnitude
            column.isEditable = false
            table.addTableColumn(column)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 4, right: 0)
        scrollView.documentView = table

        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.attach(table: table, scrollView: scrollView)
        return scrollView
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var model: any BooksTableModel
        var library: Library
        var exportAction: ExportAction
        private(set) var rows = BookTableRows.empty
        private(set) var key: BooksTableKey?
        private(set) weak var tableView: BooksNSTableView?
        private var selectedLibid: Int32?
        private var checked: Set<Int32> = []
        /// Выделение меняет код, а не пользователь — в модель не пишем.
        private var isUpdatingSelection = false

        init(model: any BooksTableModel, library: Library, exportAction: ExportAction) {
            self.model = model
            self.library = library
            self.exportAction = exportAction
        }

        func attach(table: BooksNSTableView, scrollView: NSScrollView) {
            tableView = table
            let clip = scrollView.contentView
            clip.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(clipFrameDidChange(_:)),
                name: NSView.frameDidChangeNotification, object: clip)
            layoutColumns(width: clip.frame.width)
        }

        @objc private func clipFrameDidChange(_ notification: Notification) {
            guard let clip = notification.object as? NSView else { return }
            layoutColumns(width: clip.frame.width)
        }

        /// От ширины clip view, а не панели: с постоянной полосой прокрутки
        /// колонки уже панели на её ширину.
        func layoutColumns(width: CGFloat) {
            // До первой раскладки SwiftUI ширина clip view нулевая.
            guard let tableView, width > 0 else { return }
            let layout = BookTableColumns.columnLayout(forWidth: width)
            for id in BookTableColumnID.allCases {
                guard let column = tableView.tableColumn(withIdentifier: id.identifier) else { continue }
                if let w = layout.width(of: id) {
                    column.isHidden = false
                    if column.width != w { column.width = w }
                } else {
                    column.isHidden = true
                }
            }
        }

        func apply(rows newRows: BookTableRows, key newKey: BooksTableKey,
                   selectedLibid newSelected: Int32?, checked newChecked: Set<Int32>) {
            guard let tableView else { return }
            let structural = newKey != key || newRows.count != rows.count
            let cellsChanged = newSelected != selectedLibid || newChecked != checked
            rows = newRows
            key = newKey
            selectedLibid = newSelected
            checked = newChecked
            if structural {
                withoutWritingSelection { tableView.reloadData() }
                syncSelection(of: tableView, to: newSelected)
                scroll(tableView, to: newRows.scrollTarget(selectedLibid: newSelected))
                tableView.headerView?.needsDisplay = true
            } else {
                syncSelection(of: tableView, to: newSelected)
                if cellsChanged { reloadVisibleTitleCells(of: tableView) }
            }
        }

        private func reloadVisibleTitleCells(of tableView: NSTableView) {
            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.length > 0,
                  let column = tableView.tableColumns.firstIndex(where: {
                      $0.identifier == BookTableColumnID.title.identifier })
            else { return }
            withoutWritingSelection {
                tableView.reloadData(forRowIndexes: IndexSet(integersIn: visible.location ..< NSMaxRange(visible)),
                                     columnIndexes: IndexSet(integer: column))
            }
        }

        private func scroll(_ tableView: NSTableView, to target: BookTableRows.ScrollTarget) {
            switch target {
            case .top:
                if tableView.numberOfRows > 0 { tableView.scrollRowToVisible(0) }
            case .row(let row, let header):
                if let header { tableView.scrollRowToVisible(header) }
                tableView.scrollRowToVisible(row)
            }
        }

        func withoutWritingSelection(_ body: () -> Void) {
            isUpdatingSelection = true
            defer { isUpdatingSelection = false }
            body()
        }

        func syncSelection(of tableView: NSTableView, to libid: Int32?) {
            withoutWritingSelection {
                if let libid, let row = rows.row(ofLibid: libid) {
                    if tableView.selectedRow != row {
                        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    }
                } else if tableView.selectedRow != -1 {
                    tableView.deselectAll(nil)
                }
            }
        }

        func toggleCheck(libid: Int32) {
            if model.checkedBookLibids.contains(libid) {
                model.checkedBookLibids.remove(libid)
            } else {
                model.checkedBookLibids.insert(libid)
            }
        }

        func cellText(for book: Book, column: BookTableColumnID) -> String {
            switch column {
            case .title: book.title
            case .num: book.seriesNum.map { "\($0)" } ?? "—"
            case .size: ByteCountFormatter.string(fromByteCount: Int64(book.size), countStyle: .file)
            case .date: book.dateAdded.map(DateFormat.dayMonthYear.string(from:)) ?? "—"
            case .genres: book.genreIDs.compactMap { library.genreByID[$0]?.name }.joined(separator: ", ")
            }
        }

        // MARK: Data source / delegate

        func numberOfRows(in _: NSTableView) -> Int { rows.count }

        func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
            rows.rows.indices.contains(row) && !rows.isBook(row)
        }

        func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
            rows.isBook(row) ? BooksNSTableView.bookRowHeight : BooksNSTableView.seriesHeaderHeight
        }

        func tableView(_ tableView: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("BooksTable.row")
            if let view = tableView.makeView(withIdentifier: id, owner: nil) as? BooksRowView { return view }
            let view = BooksRowView()
            view.identifier = id
            return view
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.rows.indices.contains(row) else { return nil }
            switch rows.rows[row] {
            case .seriesHeader(let series, let count):
                let id = NSUserInterfaceItemIdentifier("BooksTable.series")
                let cell = tableView.makeView(withIdentifier: id, owner: nil) as? SeriesHeaderCellView
                    ?? { let c = SeriesHeaderCellView(); c.identifier = id; return c }()
                cell.configure(series: series, count: count)
                return cell
            case .book(let book, let inSeries):
                guard let tableColumn,
                      let column = BookTableColumnID(rawValue: tableColumn.identifier.rawValue)
                else { return nil }
                if column == .title {
                    let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? BookTitleCellView
                        ?? { let c = BookTitleCellView(); c.identifier = column.identifier; return c }()
                    let libid = book.libid
                    cell.configure(book: book, inSeries: inSeries,
                                   isChecked: checked.contains(libid),
                                   isSelected: selectedLibid == libid,
                                   onToggle: { [weak self] in self?.toggleCheck(libid: libid) })
                    return cell
                }
                let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? BookTextCellView
                    ?? BookTextCellView(column: column)
                cell.configure(text: cellText(for: book, column: column))
                return cell
            }
        }

        func tableView(_: NSTableView, typeSelectStringFor _: NSTableColumn?, row: Int) -> String? {
            rows.book(at: row)?.title
        }

        func tableView(_ tableView: NSTableView,
                       selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
            let current = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
            // ⇧-стрелка может предложить {текущая, следующая}: берём не текущую.
            let candidate = proposed.first(where: { $0 != current }) ?? proposed.first
            let byKeyboard = (tableView as? BooksNSTableView)?.isHandlingKeyDown ?? false
            guard let row = rows.resolveSelection(proposed: candidate, current: current,
                                                  byKeyboard: byKeyboard)
            else { return IndexSet() }
            return IndexSet(integer: row)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection,
                  let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            guard let libid = rows.libid(at: row) else { return }
            model.selectedBookLibid = libid
            if row > 0, !rows.isBook(row - 1) { tableView.scrollRowToVisible(row - 1) }
        }
    }
}
```

Замечание: если компилятор требует, у `Coordinator` добавить `nonisolated deinit {}` — как в `LazyListTable.swift:131` (ICE только в Release; здесь класс не generic, поэтому не ожидается).

- [ ] **Step 4: Прогон — зелёный.** Если `deepLinkSelects` или `newKeyWithoutSelected` красные из-за записи выбора при `reloadData` — проверить, что и `reloadData`, и `syncSelection` идут под `withoutWritingSelection`.

- [ ] **Step 5: Коммит**

```bash
cd /Users/alexey/code/fb-loader && git add "FB Loader/FB Loader/UI/BooksTable" "FB Loader/FB LoaderTests/BooksTableCoordinatorTests.swift" && git commit -m "feat(books-table): NSTableView и координатор — данные, выбор, колонки

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Клавиатура, пробел, меню, hover

**Files:**
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksNSTableView.swift` (`BooksNSTableView`)
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksTableRepresentable.swift` (`Coordinator`)
- Test: `FB Loader/FB LoaderTests/BooksTableCoordinatorTests.swift` (дописать; `BooksTableHarness`, `BooksTableFixture` — из задачи 5)

**Interfaces:**
- Consumes: `spaceRoute(lastTypeSelectKey:now:)` (задача 2), `BooksTableHarness` (задача 5).
- Produces:
  ```swift
  extension BooksNSTableView {
      var lastTypeSelectKey: Date?; var now: () -> Date
      var onSpaceToggle: (() -> Void)?; var menuProvider: ((Int) -> NSMenu?)?
      private(set) var hoveredRow: Int; func setHoveredRow(_ row: Int); func updateHoverFromMouse()
  }
  extension Coordinator { func toggleCheckAtSelectedRow(); func contextMenu(forRow row: Int) -> NSMenu?; @objc func exportChecked(_:) }
  ```

Правила:
- Стрелки с любыми модификаторами и type-select — штатный `super.keyDown`; своей обработки стрелок нет. Флаг `isHandlingKeyDown` уже поднимается (задача 5).
- Пробел (`charactersIgnoringModifiers == " "`, без ⌘⌃⌥): `spaceRoute(lastTypeSelectKey, now())` → `.toggleCheck` — `onSpaceToggle?()` и выход без `super` (без звука, даже без выделения); `.typeSelect` — `super.keyDown` (пробел уходит в поиск).
- Время последней буквы type-select: `keyDown` печатного символа без ⌘⌃⌥, кроме пробела, ставит `lastTypeSelectKey = now()`. Печатный — непустой, без управляющих символов и без функциональных (U+F700…U+F8FF: стрелки, F-клавиши). Shift и CapsLock допускаются (заглавные буквы).
- `toggleCheckAtSelectedRow`: книга в `tableView.selectedRow` → `toggleCheck(libid:)`; иначе ничего. Выбранная в модели книга, которой нет в строках, — ничего (`selectedRow == -1`).
- `menu(for:)` подкласса без `super`: строка под курсором → `menuProvider?(row)`. `clickedRow` не выставляется, обводки нет, выбор не меняется.
- `contextMenu(forRow:)`: строка книги → `NSMenu` с одним пунктом «Выгрузить отмеченные (N)», N = `model.checkedBookLibids.count` в момент открытия, `autoenablesItems = false`, `isEnabled = N > 0`, действие → `exportAction.perform()`. Заголовок серии, пустое место (`row == -1`) → `nil`.
- Hover: `NSTrackingArea` (`.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect`) на таблице; `mouseMoved` → `setHoveredRow(row(at:))`, `mouseExited` → `-1`. После прокрутки (`NSView.boundsDidChangeNotification` clip view, `postsBoundsChangedNotifications = true`) и после структурного `apply` — `updateHoverFromMouse()` по `window.mouseLocationOutsideOfEventStream`. `reloadData` сбрасывает `hoveredRow = -1` (индекс устарел). Новые строки получают `isHovered` в `tableView(_:didAdd:forRow:)`.

- [ ] **Step 1: Тесты** — дописать в `BooksTableCoordinatorTests.swift`:

```swift
@MainActor
private func keyEvent(_ characters: String, keyCode: UInt16,
                      modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                     windowNumber: 0, context: nil, characters: characters,
                     charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
}

@MainActor
private func arrow(_ scalar: Int, keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    keyEvent(String(Character(UnicodeScalar(UInt32(scalar))!)), keyCode: keyCode,
             modifiers: modifiers.union([.numericPad, .function]))
}

@MainActor private func down(_ m: NSEvent.ModifierFlags = []) -> NSEvent { arrow(NSDownArrowFunctionKey, keyCode: 125, m) }
@MainActor private func up(_ m: NSEvent.ModifierFlags = []) -> NSEvent { arrow(NSUpArrowFunctionKey, keyCode: 126, m) }
@MainActor private func space() -> NSEvent { keyEvent(" ", keyCode: 49) }

@Suite("BooksTable keyboard and menu")
@MainActor
struct BooksTableKeyboardTests {
    @Test("↓, ⇧↓ и ⌥↓: выбор перескакивает заголовок серии и пишется в модель")
    func arrowsSkipHeader() {
        for mods: NSEvent.ModifierFlags in [[], [.shift], [.option]] {
            let h = BooksTableHarness()
            h.select(row: 1)
            h.model.selectionWrites.removeAll()
            h.table.keyDown(with: down(mods))
            #expect(h.table.selectedRow == 3, "mods \(mods.rawValue)")
            #expect(h.model.selectionWrites == [20], "mods \(mods.rawValue)")
        }
    }

    @Test("на последней книге ↓ — выбор на месте")
    func downAtEnd() {
        let h = BooksTableHarness()
        h.select(row: 4)
        h.model.selectionWrites.removeAll()
        h.table.keyDown(with: down())
        #expect(h.table.selectedRow == 4)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("без выбора ↓ при заголовке в строке 0 — первая книга; ↑ на ней — на месте")
    func headerAtTop() {
        let series = Array(BooksTableFixture.books[2...])
        let h = BooksTableHarness(books: series)
        h.table.keyDown(with: down())
        #expect(h.table.selectedRow == 1)
        h.table.keyDown(with: up())
        #expect(h.table.selectedRow == 1)
    }

    @Test("пробел с выделением переключает галочку туда и обратно, выбор не меняется")
    func spaceToggles() {
        let h = BooksTableHarness()
        h.select(row: 0)
        h.model.selectionWrites.removeAll()
        h.table.keyDown(with: space())
        #expect(h.model.checkedBookLibids == [10])
        h.table.keyDown(with: space())
        #expect(h.model.checkedBookLibids.isEmpty)
        #expect(h.table.selectedRow == 0)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("пробел без выделения — ничего; выбранной в модели книги нет в строках — ничего")
    func spaceWithoutSelection() {
        let h = BooksTableHarness()
        h.table.keyDown(with: space())
        #expect(h.model.checkedBookLibids.isEmpty)
        let hidden = BooksTableHarness(selected: 99)
        hidden.table.keyDown(with: space())
        #expect(hidden.model.checkedBookLibids.isEmpty)
    }

    @Test("пробел меньше чем через секунду после буквы уходит в type-select")
    func spaceAfterLetter() {
        let h = BooksTableHarness()
        h.select(row: 0)
        var clock = Date(timeIntervalSinceReferenceDate: 1000)
        h.table.now = { clock }
        h.table.keyDown(with: keyEvent("б", keyCode: 43))
        #expect(h.table.lastTypeSelectKey == clock)
        clock += 0.5
        h.table.keyDown(with: space())
        #expect(h.model.checkedBookLibids.isEmpty)
    }

    @Test("меню на книге: один пункт с N, неактивен при N = 0, действие — ExportAction")
    func contextMenu() {
        let h = BooksTableHarness(checked: [10, 20])
        var exports = 0
        h.exportAction.perform = { exports += 1 }
        let menu = h.coordinator.contextMenu(forRow: 0)
        #expect(menu?.items.count == 1)
        #expect(menu?.items.first?.title == "Выгрузить отмеченные (2)")
        #expect(menu?.items.first?.isEnabled == true)
        menu?.performActionForItem(at: 0)
        #expect(exports == 1)

        h.model.checkedBookLibids = []
        let empty = h.coordinator.contextMenu(forRow: 3)
        #expect(empty?.items.first?.title == "Выгрузить отмеченные (0)")
        #expect(empty?.items.first?.isEnabled == false)
    }

    @Test("меню на заголовке серии и пустом месте — nil")
    func noMenuOnHeader() {
        let h = BooksTableHarness()
        #expect(h.coordinator.contextMenu(forRow: 2) == nil)
        #expect(h.coordinator.contextMenu(forRow: -1) == nil)
    }

    @Test("ПКМ по невыделенной книге: меню есть, выбор и модель не меняются")
    func rightClickKeepsSelection() {
        let h = BooksTableHarness()
        h.select(row: 0)
        h.model.selectionWrites.removeAll()
        let rect = h.table.rect(ofRow: 3)
        let point = h.table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [],
                                       timestamp: 0, windowNumber: h.window.windowNumber, context: nil,
                                       eventNumber: 0, clickCount: 1, pressure: 1)!
        #expect(h.table.menu(for: event) != nil)
        #expect(h.table.selectedRow == 0)
        #expect(h.model.selectionWrites.isEmpty)
    }

    @Test("hover сбрасывается при перезагрузке строк")
    func hoverResetsOnReload() {
        let h = BooksTableHarness()
        h.table.setHoveredRow(1)
        #expect(h.table.hoveredRow == 1)
        // reloadData напрямую: apply ещё пересчитывает hover по реальному курсору — тест зависел бы от мыши.
        h.table.reloadData()
        #expect(h.table.hoveredRow == -1)
    }
}
```

- [ ] **Step 2: Прогон — красный** (`value of type 'BooksNSTableView' has no member 'now'` и т. п.).

- [ ] **Step 3a: `BooksNSTableView`** — заменить `keyDown`, `reloadData` и дописать:

```swift
    var lastTypeSelectKey: Date?
    var now: () -> Date = Date.init
    var onSpaceToggle: (() -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?
    private(set) var hoveredRow = -1
    private var hoverArea: NSTrackingArea?

    override func reloadData() {
        reloadDataCount += 1
        hoveredRow = -1
        super.reloadData()
    }

    override func keyDown(with event: NSEvent) {
        let commandKeys = event.modifierFlags.intersection([.command, .control, .option])
        if commandKeys.isEmpty, event.charactersIgnoringModifiers == " " {
            if spaceRoute(lastTypeSelectKey: lastTypeSelectKey, now: now()) == .toggleCheck {
                onSpaceToggle?()
                return
            }
        } else if commandKeys.isEmpty, Self.isPrintable(event.characters) {
            lastTypeSelectKey = now()
        }
        isHandlingKeyDown = true
        defer { isHandlingKeyDown = false }
        super.keyDown(with: event)
    }

    private static func isPrintable(_ characters: String?) -> Bool {
        guard let characters, !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !(0xF700 ... 0xF8FF).contains($0.value)
        }
    }

    /// Без `super`: штатная реализация выставляет `clickedRow` и обводит строку.
    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setHoveredRow(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHoveredRow(-1)
    }

    /// После прокрутки колёсиком `mouseMoved` не приходит — строка под курсором другая.
    func updateHoverFromMouse() {
        guard let window else { setHoveredRow(-1); return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHoveredRow(visibleRect.contains(point) ? row(at: point) : -1)
    }

    func setHoveredRow(_ row: Int) {
        guard row != hoveredRow else { return }
        if (0 ..< numberOfRows).contains(hoveredRow) {
            (rowView(atRow: hoveredRow, makeIfNecessary: false) as? BooksRowView)?.isHovered = false
        }
        hoveredRow = row
        if (0 ..< numberOfRows).contains(row) {
            (rowView(atRow: row, makeIfNecessary: false) as? BooksRowView)?.isHovered = true
        }
    }
```

- [ ] **Step 3b: `Coordinator`** — в `attach(table:scrollView:)` после строки с `frameDidChangeNotification` добавить:

```swift
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(clipBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification, object: clip)
            table.onSpaceToggle = { [weak self] in self?.toggleCheckAtSelectedRow() }
            table.menuProvider = { [weak self] row in self?.contextMenu(forRow: row) }
```

В ветку `if structural` метода `apply` последней строкой добавить `tableView.updateHoverFromMouse()`. Дописать методы:

```swift
        @objc private func clipBoundsDidChange(_: Notification) {
            tableView?.updateHoverFromMouse()
        }

        func toggleCheckAtSelectedRow() {
            guard let tableView, let libid = rows.libid(at: tableView.selectedRow) else { return }
            toggleCheck(libid: libid)
        }

        /// Выгружаются книги с галочками, а не строка под курсором.
        func contextMenu(forRow row: Int) -> NSMenu? {
            guard rows.isBook(row) else { return nil }
            let count = model.checkedBookLibids.count
            let menu = NSMenu()
            menu.autoenablesItems = false
            let item = NSMenuItem(title: "Выгрузить отмеченные (\(count))",
                                  action: #selector(exportChecked(_:)), keyEquivalent: "")
            item.target = self
            item.isEnabled = count > 0
            menu.addItem(item)
            return menu
        }

        @objc func exportChecked(_: Any?) { exportAction.perform() }

        func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
            (rowView as? BooksRowView)?.isHovered = row == (tableView as? BooksNSTableView)?.hoveredRow
        }
```

- [ ] **Step 4: Прогон — зелёный.** Если `arrowsSkipHeader` красный только для `[.option]` (штатный `NSTableView` не двигает выбор по ⌥↓) — свою обработку стрелок не писать (спека: «своего `keyDown` для стрелок нет»), остановиться и сообщить контроллеру. Если красные все стрелки — проверить, что `keyDown` таблицы зовёт `super` и что флаг `isHandlingKeyDown` поднят на его время.

- [ ] **Step 5: Коммит**

```bash
cd /Users/alexey/code/fb-loader && git add "FB Loader/FB Loader/UI/BooksTable" "FB Loader/FB LoaderTests/BooksTableCoordinatorTests.swift" && git commit -m "feat(books-table): клавиатура, пробел, меню и hover

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Шапка колонок и фильтр по дате

**Files:**
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksNSTableView.swift` — `DateHeaderState`, `DatePress`, `BooksHeaderCell`, `BooksHeaderView`
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksTableRepresentable.swift` — шапка в `makeScrollView`, поповер в `Coordinator`
- Test: `FB Loader/FB LoaderTests/BooksTableCoordinatorTests.swift` (дописать; `BooksTableHarness` из задачи 5)

**Interfaces:**
- Consumes: `DateFilterPopover(current:onApply:)` (`UI/BooksTable/DateFilterPopover.swift:23`, не менять), `model.applyDateFilter(_:)`, `BookTableColumnID.headerTitle`.
- Produces:
  ```swift
  enum DateHeaderState: Equatable { case normal, active, disabled }
  enum DatePress: Equatable { case open, close, ignore }
  final class BooksHeaderCell: NSTableHeaderCell { init(column: BookTableColumnID); let column: BookTableColumnID
      static let labelTop: CGFloat; static func contentRect(for: BookTableColumnID, in: NSRect) -> NSRect }
  final class BooksHeaderView: NSTableHeaderView { static let height: CGFloat /* 33 */
      var dateState: DateHeaderState; private(set) var isDatePressed: Bool
      var datePressAction: ((TimeInterval) -> DatePress)?; var performDatePress: ((DatePress) -> Void)? }
  // Coordinator: в объявлении класса добавляется NSPopoverDelegate
  extension Coordinator {
      var dateHeaderState: DateHeaderState; var isDatePopoverShown: Bool
      func datePress(at timestamp: TimeInterval) -> DatePress; func perform(_ action: DatePress)
      func notePopoverClosed(at timestamp: TimeInterval?) }
  ```

Правила (из спеки):
- `table.headerView = BooksHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 33))`, `table.cornerView = nil`. Высота 33 включает линию 1pt `separatorColor` внизу (72–73pt от верха панели: над scroll view SwiftUI-строка 40pt). Фон шапки — сплошной `windowBackgroundColor`, без вертикальных разделителей: `draw(_:)` шапки сам заливает фон, рисует ячейки видимых колонок по `headerRect(ofColumn:)` и линию; `super.draw` не зовётся.
- Подписи: 10pt semibold, верхний регистр, `kern 0.6`, `secondaryLabelColor`; верх текста — 2pt от верха шапки (`labelTop`). Область содержимого (`contentRect`): `title` — от 16 + 28 + 10 = 54 до правого края, по левому краю; `num/size/date` — с 10 слева шириной 50/80/100, по правому краю; `genres` — с 10 слева до 16 справа, по левому краю.
- «Дата»: подпись + `chevron.down` 7pt bold, промежуток 3; шеврон у правого края области содержимого, подпись левее. Цвет: `.normal` — `secondaryLabelColor`, `.active` (фильтр есть) — `controlAccentColor`, `.disabled` (нет контекста) — `tertiaryLabelColor`. Пока кнопка мыши зажата над колонкой — всё «Дата» с альфой 0,5.
- `mouseDown` шапки без `super`: не над «Датой» — игнор. Над «Датой» — `datePressAction(event.timestamp)`; `.ignore` — игнор; иначе подсветка нажатия и цикл `window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp])` до отпускания; отпустили над колонкой — `performDatePress(action)`.
- `datePress(at:)`: поповер показан, или его закрыло это же событие (`notePopoverClosed` с тем же `timestamp` — transient-поповер закрывается тем же кликом по «Дате» раньше, чем тот дойдёт до шапки) → `.close`; нет контекста → `.ignore`; иначе `.open`.
- Поповер: `NSPopover`, `behavior = .transient`, новый `NSHostingController(rootView: DateFilterPopover(current: model.dateFilter) { … })` на каждое открытие, `sizingOptions = [.preferredContentSize]` (календарь растёт внутри поповера), `show(relativeTo: header.headerRect(ofColumn: date), of: header, preferredEdge: .maxY)` — во flipped-шапке `.maxY` — низ, поповер под заголовком стрелкой к нему. `onApply` → `model.applyDateFilter(next)` и `performClose`. `popoverWillClose` → `notePopoverClosed(at: NSApp.currentEvent?.timestamp)`; `popoverDidClose` → `datePopover = nil`.
- VoiceOver: мышь не доходит до `super.mouseDown` шапки, поэтому `tableView(_:didClick:)` делегата приходит только от штатного нажатия доступности на ячейку; для `date` → `perform(datePress(at: NSApp.currentEvent?.timestamp ?? -1))`. Срабатывает ли — проверяет Alexey; иначе пути нет (решение в спеке).
- В `apply` при структурной смене: `(tableView.headerView as? BooksHeaderView)?.dateState = dateHeaderState` перед `needsDisplay = true`.
- Клик по заголовкам других колонок ничего не меняет (нет сортировки, выбора колонки).

- [ ] **Step 1: Тесты** — дописать:

```swift
@Suite("BooksTable header")
@MainActor
struct BooksTableHeaderTests {
    private let dates = DateRangeFilter(from: Date(timeIntervalSinceReferenceDate: 0),
                                        to: Date(timeIntervalSinceReferenceDate: 86_400))

    @Test("шапка 33pt, без cornerView, у каждой колонки своя ячейка шапки")
    func headerSetup() {
        let h = BooksTableHarness()
        #expect(h.table.headerView is BooksHeaderView)
        #expect(h.table.headerView?.frame.height == 33)
        #expect(h.table.cornerView == nil)
        for column in h.table.tableColumns {
            #expect((column.headerCell as? BooksHeaderCell)?.column.identifier == column.identifier)
        }
    }

    @Test("состояние «Даты»: без контекста — неактивна, без фильтра — обычная, с фильтром — акцент")
    func dateState() {
        let h = BooksTableHarness(context: nil)
        let header = h.table.headerView as? BooksHeaderView
        #expect(header?.dateState == .disabled)
        h.apply(books: BooksTableFixture.books, context: .author(1))
        #expect(header?.dateState == .normal)
        h.apply(books: BooksTableFixture.books, context: .author(1), dates: dates)
        #expect(header?.dateState == .active)
    }

    @Test("нажатие на «Дату»: без контекста — игнор, с контекстом — открыть")
    func datePressByContext() {
        #expect(BooksTableHarness(context: nil).coordinator.datePress(at: 1) == .ignore)
        #expect(BooksTableHarness().coordinator.datePress(at: 1) == .open)
    }

    @Test("клик, закрывший transient-поповер, поповер заново не открывает")
    func pressThatClosedPopover() {
        let c = BooksTableHarness().coordinator
        c.notePopoverClosed(at: 42)
        #expect(c.datePress(at: 42) == .close)
        #expect(c.datePress(at: 43) == .open)
    }

    @Test("нажатие на «Дату» без контекста поповер не открывает")
    func noPopoverWithoutContext() {
        let h = BooksTableHarness(context: nil)
        let dateColumn = h.table.tableColumn(withIdentifier: BookTableColumnID.date.identifier)!
        h.coordinator.tableView(h.table, didClick: dateColumn)
        h.coordinator.perform(.open)
        #expect(!h.coordinator.isDatePopoverShown)
    }

    @Test("области подписей: Название с 54pt, Дата 100pt после промежутка, шеврон в 16pt от края последней колонки")
    func contentRects() {
        let frame = NSRect(x: 0, y: 0, width: 500, height: 33)
        #expect(BooksHeaderCell.contentRect(for: .title, in: frame).minX == 54)
        let date = NSRect(x: 600, y: 0, width: 126, height: 33)
        let dateContent = BooksHeaderCell.contentRect(for: .date, in: date)
        #expect(dateContent.minX == 610)
        #expect(dateContent.width == 100)
        #expect(date.maxX - dateContent.maxX == 16)
        let genres = BooksHeaderCell.contentRect(for: .genres, in: NSRect(x: 800, y: 0, width: 246, height: 33))
        #expect(genres.minX == 810)
        #expect(genres.width == 220)
    }
}
```

- [ ] **Step 2: Прогон — красный** (`cannot find type 'BooksHeaderView'`).

- [ ] **Step 3a: `BooksNSTableView.swift`** — дописать:

```swift
enum DateHeaderState: Equatable { case normal, active, disabled }
enum DatePress: Equatable { case open, close, ignore }

final class BooksHeaderCell: NSTableHeaderCell {
    let column: BookTableColumnID
    /// Верх подписи от верха шапки: 40pt строки заголовка + 2 = 42pt от верха панели, как в SwiftUI-шапке.
    static let labelTop: CGFloat = 2

    init(column: BookTableColumnID) {
        self.column = column
        super.init(textCell: column.headerTitle)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func contentRect(for column: BookTableColumnID, in frame: NSRect) -> NSRect {
        let s = BookTableColumns.spacing
        func fixed(_ width: CGFloat) -> NSRect {
            NSRect(x: frame.minX + s, y: frame.minY, width: width, height: frame.height)
        }
        switch column {
        case .title:
            let x = frame.minX + BookTableColumns.rowInset + BookTableColumns.checkboxWidth + s
            return NSRect(x: x, y: frame.minY, width: frame.maxX - x, height: frame.height)
        case .num: return fixed(BookTableColumns.numWidth)
        case .size: return fixed(BookTableColumns.sizeWidth)
        case .date: return fixed(BookTableColumns.dateWidth)
        case .genres:
            return NSRect(x: frame.minX + s, y: frame.minY,
                          width: frame.width - s - BookTableColumns.rowInset, height: frame.height)
        }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let header = controlView as? BooksHeaderView
        var color = NSColor.secondaryLabelColor
        if column == .date {
            switch header?.dateState ?? .normal {
            case .normal: break
            case .active: color = .controlAccentColor
            case .disabled: color = .tertiaryLabelColor
            }
        }
        let text = NSAttributedString(
            string: column.headerTitle.uppercased(),
            attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                         .kern: 0.6, .foregroundColor: color])
        let size = text.size()
        let content = Self.contentRect(for: column, in: cellFrame)
        let top = cellFrame.minY + Self.labelTop

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if column == .date, header?.isDatePressed == true {
            NSGraphicsContext.current?.cgContext.setAlpha(0.5)
        }
        switch column {
        case .title, .genres:
            text.draw(at: NSPoint(x: content.minX, y: top))
        case .num, .size:
            text.draw(at: NSPoint(x: content.maxX - size.width, y: top))
        case .date:
            let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
            let cs = chevron?.size ?? .zero
            let chevronX = content.maxX - cs.width
            text.draw(at: NSPoint(x: chevronX - 3 - size.width, y: top))
            chevron?.draw(in: NSRect(x: chevronX, y: top + (size.height - cs.height) / 2,
                                     width: cs.width, height: cs.height),
                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

final class BooksHeaderView: NSTableHeaderView {
    static let height: CGFloat = 33
    var dateState: DateHeaderState = .disabled
    private(set) var isDatePressed = false
    var datePressAction: ((TimeInterval) -> DatePress)?
    var performDatePress: ((DatePress) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        if let tableView {
            for (index, column) in tableView.tableColumns.enumerated() where !column.isHidden {
                column.headerCell.draw(withFrame: headerRect(ofColumn: index), in: self)
            }
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    /// Без `super`: у колонок нет сортировки и выбора, кликабельна только «Дата».
    override func mouseDown(with event: NSEvent) {
        guard let tableView else { return }
        let index = column(at: convert(event.locationInWindow, from: nil))
        guard index >= 0,
              tableView.tableColumns[index].identifier == BookTableColumnID.date.identifier,
              let action = datePressAction?(event.timestamp), action != .ignore
        else { return }
        let rect = headerRect(ofColumn: index)
        var inside = true
        setDatePressed(true)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            inside = rect.contains(convert(next.locationInWindow, from: nil))
            setDatePressed(inside)
            if next.type == .leftMouseUp { break }
        }
        setDatePressed(false)
        if inside { performDatePress?(action) }
    }

    private func setDatePressed(_ pressed: Bool) {
        guard pressed != isDatePressed else { return }
        isDatePressed = pressed
        needsDisplay = true
    }
}
```

- [ ] **Step 3b: `makeScrollView`** — в цикле колонок после `column.title = …` добавить `column.headerCell = BooksHeaderCell(column: id)`; после цикла:

```swift
        let header = BooksHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: BooksHeaderView.height))
        header.datePressAction = { [weak coordinator] timestamp in coordinator?.datePress(at: timestamp) ?? .ignore }
        header.performDatePress = { [weak coordinator] action in coordinator?.perform(action) }
        table.headerView = header
        table.cornerView = nil
```

- [ ] **Step 3c: `Coordinator`** — объявление класса: `final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSPopoverDelegate`. Свойства:

```swift
        private var datePopover: NSPopover?
        private var lastPopoverCloseTimestamp: TimeInterval?
```

В `apply`, ветка `structural`: заменить `tableView.headerView?.needsDisplay = true` на

```swift
                if let header = tableView.headerView as? BooksHeaderView { header.dateState = dateHeaderState }
                tableView.headerView?.needsDisplay = true
```

Методы:

```swift
        var dateHeaderState: DateHeaderState {
            guard let key, key.context != nil else { return .disabled }
            return key.dates == nil ? .normal : .active
        }

        var isDatePopoverShown: Bool { datePopover?.isShown == true }

        func datePress(at timestamp: TimeInterval) -> DatePress {
            if isDatePopoverShown || lastPopoverCloseTimestamp == timestamp { return .close }
            return dateHeaderState == .disabled ? .ignore : .open
        }

        func perform(_ action: DatePress) {
            switch action {
            case .ignore: break
            case .close: datePopover?.performClose(nil)
            case .open: showDatePopover()
            }
        }

        func notePopoverClosed(at timestamp: TimeInterval?) {
            lastPopoverCloseTimestamp = timestamp
        }

        private func showDatePopover() {
            guard dateHeaderState != .disabled, !isDatePopoverShown,
                  let tableView, let header = tableView.headerView,
                  let column = tableView.tableColumns.firstIndex(where: {
                      $0.identifier == BookTableColumnID.date.identifier })
            else { return }
            let popover = NSPopover()
            popover.behavior = .transient
            popover.delegate = self
            let host = NSHostingController(rootView: DateFilterPopover(current: model.dateFilter) { [weak self] next in
                self?.model.applyDateFilter(next)
                self?.datePopover?.performClose(nil)
            })
            host.sizingOptions = [.preferredContentSize]
            popover.contentViewController = host
            datePopover = popover
            // Шапка flipped: .maxY — её нижний край, поповер под заголовком.
            popover.show(relativeTo: header.headerRect(ofColumn: column), of: header, preferredEdge: .maxY)
        }

        func popoverWillClose(_: Notification) {
            notePopoverClosed(at: NSApp.currentEvent?.timestamp)
        }

        func popoverDidClose(_: Notification) {
            datePopover = nil
        }

        /// Мышь сюда не доходит (шапка не зовёт super.mouseDown) — только нажатие VoiceOver.
        func tableView(_: NSTableView, didClick tableColumn: NSTableColumn) {
            guard tableColumn.identifier == BookTableColumnID.date.identifier else { return }
            perform(datePress(at: NSApp.currentEvent?.timestamp ?? -1))
        }
```

- [ ] **Step 4: Прогон — зелёный.**

- [ ] **Step 5: Коммит**

```bash
cd /Users/alexey/code/fb-loader && git add "FB Loader/FB Loader/UI/BooksTable" "FB Loader/FB LoaderTests/BooksTableCoordinatorTests.swift" && git commit -m "feat(books-table): шапка колонок и поповер фильтра по дате

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Подмена в BooksTableView, удаление старой таблицы

**Files:**
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift`
- Modify: `FB Loader/FB Loader/UI/MainWindowView.swift:98-99` (только комментарий)

**Interfaces:**
- Consumes: `BooksTableRepresentable(state:library:rows:key:exportAction:)`, `BookTableRows.build`, `BooksTableKey` (задачи 1, 5).
- Produces: `BooksTableView(library:exportAction:)` — сигнатура прежняя, `MainWindowView:26` не меняется.

Изменение без новой логики: проверяется полным набором тестов (существующие + задачи 1–7) и ручной проверкой. Нового теста нет: SwiftUI `body` в проекте не тестируется.

- [ ] **Step 1: `BooksTableView.swift`** — `ExportAction`, `LanguageFilterLabel`, `LanguageFilterPicker` не трогать. `BooksTableView` и `BooksTableContent` привести к виду:

```swift
struct BooksTableView: View {
    let library: Library
    let exportAction: ExportAction

    var body: some View {
        BooksTableContent(library: library, exportAction: exportAction)
    }
}

private struct BooksTableContent: View {
    let library: Library
    let exportAction: ExportAction
    @Environment(AppState.self) private var state

    private var context: BooksByContext.Context? { /* без изменений, :42-49 */ }

    private var visibleBooks: (books: [Book], total: Int) { /* без изменений, :51-57 */ }

    var body: some View {
        // Выборка и строки — только здесь и только при смене контекста, языка,
        // фильтра дат: выбор и галочки body не читает, их читает updateNSView.
        let result = visibleBooks
        let rows = BookTableRows.build(books: result.books, library: library)
        let key = BooksTableKey(context: context, language: state.languageFilter, dates: state.dateFilter)
        VStack(spacing: 0) {
            titleRow(count: result.books.count, total: result.total)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 40, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
            BooksTableRepresentable(state: state, library: library, rows: rows, key: key,
                                    exportAction: exportAction)
        }
    }

    // titleRow(count:total:), counter(count:total:), titleLabel, booksCountLabel — без изменений.
}
```

Удалить: `@State private var columns` и `.environment(\.bookTableColumns…)` / `.onGeometryChange` в `BooksTableView`; в `BooksTableContent` — `@State showDateFilter`, `GroupedRow`, `groups(from:)`, `bookRow(for:indented:state:)`, `header(count:total:)`, `dateColumnButton`, `seriesGroupHeader`, `@Bindable var s`; структуру `ColumnsHeaderRow`.

- [ ] **Step 2: `MainWindowView.swift:98-99`** — заменить комментарий над `.toolbarBackground(.visible, for: .windowToolbar)` (строку кода не трогать):

```swift
        // Непрозрачная панель окна: под прозрачной просвечивает прокручиваемое
        // содержимое, которое macOS пускает под неё.
```

- [ ] **Step 3: Проверка, что окно поиска не задето** (текстовый поиск, допустим grep):

```bash
cd "/Users/alexey/code/fb-loader/FB Loader/FB Loader" && grep -rn "BookRow(" UI && grep -rn "GroupedRow\|ColumnsHeaderRow\|dateColumnButton\|seriesGroupHeader\|LazyVStack" UI/BooksTable
```

Ожидается: `BookRow(` — только в `UI/Search/SearchAuthorBlock.swift`, `SearchSeriesBlock.swift`, `SearchBooksBucketView.swift`; вторая команда — пусто. `git diff --stat main -- "FB Loader/FB Loader/UI/Search" "FB Loader/FB Loader/UI/BooksTable/BookRow.swift" "FB Loader/FB Loader/UI/Components/CompactCheckbox.swift"` — пусто.

- [ ] **Step 4: Прогон — зелёный** (включая `SearchCoordinatorTests`, `BookTableColumnsTests`).

- [ ] **Step 5: Коммит**

```bash
cd /Users/alexey/code/fb-loader && git add "FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift" "FB Loader/FB Loader/UI/MainWindowView.swift" && git commit -m "feat(books-table): таблица книг на NSTableView вместо LazyVStack

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Спеки и чистка

**Files:**
- Modify: `docs/superpowers/specs/2026-08-07-books-date-filter-design.md` (разделы «Заголовок колонки», «Шапка внутри прокрутки»)
- Modify: `docs/superpowers/specs/2026-05-01-ui-polish-design.md` (§3.2 строка чекбокса, §3.4)
- Modify: `docs/superpowers/specs/2026-05-04-fuzzy-search-design.md:188`
- Modify: `FB Loader/FB Loader/UI/BooksTable/BookRow.swift:3-7` (только doc-комментарий)

Правки — по одной фразе, плотно, со ссылкой на `2026-10-15-books-nstableview-design.md`:

- [ ] **Step 1: books-date-filter, «Заголовок колонки»** — первую фразу заменить: «Ячейка шапки `NSTableView` (с 2026-10-15, см. [2026-10-15-books-nstableview-design.md](2026-10-15-books-nstableview-design.md)): подпись и шеврон справа в тех же 100pt колонки «Дата».» Остальное раздела оставить.
- [ ] **Step 2: books-date-filter, «Шапка внутри прокрутки»** — в начало раздела: «Заменено 2026-10-15: шапка колонок — `NSTableHeaderView` той же `NSScrollView`, ширины колонок — от ширины clip view ([2026-10-15-books-nstableview-design.md](2026-10-15-books-nstableview-design.md)).» Абзац про `.toolbarBackground` оставить.
- [ ] **Step 3: ui-polish** — §3.2, строка 1 таблицы: контент «`Toggle` без label» → «галочка 14×14 (`BookCheckbox` в главном окне, `CompactCheckbox` в окне поиска)»; §3.4: «Остаётся в `bookRow` как сейчас (см. `BooksTableView.swift:116-123`).» → «В главном окне — `menu(for:)` таблицы, без обводки строки ([2026-10-15-books-nstableview-design.md](2026-10-15-books-nstableview-design.md)).»
- [ ] **Step 4: fuzzy-search:188** — «Те же колонки, что в `BookRow` основной таблицы» → «Те же колонки, что в основной таблице (окно поиска рисует их `BookRow`)».
- [ ] **Step 5: `BookRow.swift:3-7`** — doc-комментарий заменить на:

```swift
/// Строка книги окна поиска (`SearchWindowView`): выбор и галочка — через
/// `@Binding`, контекстное меню — необязательное. Главное окно рисует книги
/// в `NSTableView` (`BooksTableRepresentable`).
```

- [ ] **Step 6: Проверка остатков**

```bash
cd /Users/alexey/code/fb-loader && grep -rn "LazyVStack\|onTapGesture" "FB Loader/FB Loader/UI/BooksTable"; grep -rn "BooksTableView.swift:1[0-9][0-9]" docs/superpowers/specs | grep -v books-nstableview
```

Первая команда — пусто (кроме `BookRow.swift`, который остаётся для окна поиска: там `onTapGesture` допустим). Вторая — только исторические ссылки в разделах «Файлы»/«Реализация» старых спек; их не трогать.

- [ ] **Step 7: Прогон — зелёный.**

- [ ] **Step 8: Коммит**

```bash
cd /Users/alexey/code/fb-loader && git add docs/superpowers/specs "FB Loader/FB Loader/UI/BooksTable/BookRow.swift" && git commit -m "docs(spec): таблица книг на NSTableView — правки смежных спек

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Ручная проверка (Alexey)

До реализации — скриншоты текущей таблицы (широкая и узкая панель, автор с сериями, активный фильтр дат) как эталон.

- Вид совпадает с эталоном: шапка (линия на уровне линии сайдбара), подписи колонок над значениями, отступ книг серии, высоты строк, галочки, hover. Первая строка не уходит под шапку (иначе `contentInsets.top`).
- Выделение: акцентное с фокусом, серое без; название жирное; галочка на выделенной строке различима во включённом и выключенном состоянии, с фокусом и без.
- Сужение панели: «Жанры» исчезают раньше «Размера», «Дата» остаётся, подписи не разъезжаются.
- Режим «всегда показывать полосы прокрутки»: подписи над значениями.
- Tab: фильтр → список → таблица → фильтр; Shift-Tab обратно; то же с включённой «Навигацией с клавиатуры».
- ↑/↓ (и с ⇧) на крупном жанре: заголовки перескакиваются, края стоят, строка в видимости, у первой книги серии виден заголовок, карточка следует; зажатая ↓ не роняет карточку.
- Type-select: набор «Война и» находит книгу, галочка не ставится; пробел через секунду — галочка.
- Пробел ставит и снимает галочку; клик по галочке выбор и фокус не меняет.
- Клик по заголовку серии, пустому месту, заголовкам колонок (кроме «Даты») ничего не меняет.
- ПКМ: «Выгрузить отмеченные (N)», неактивен без галочек, выгружаются книги с галочками; обводки строки нет; на заголовке серии меню нет.
- Фильтр дат: клик по «Дата» — поповер под заголовком; календарь раскрывается целиком; Esc и клик вне закрывают; Enter применяет; повторный клик по «Дате» закрывает; «Найти» только после правки; цвет заголовка, счётчик «N из M · диапазон», крестик; без контекста заголовок неактивен; смена автора снимает фильтр.
- Смена автора/языка/даты гасит выбор и галочки, таблица — в начале; deep-link по чипу — книга выделена в новом контексте, видна вместе с заголовком серии.
- Hover не залипает после прокрутки колёсиком.
- Крупный жанр (десятки тысяч книг): переключение и прокрутка без задержек; ресайз окна не дёргает таблицу.
- Тёмная тема.
- VoiceOver читает строки и галочки; нажатие на «Дату» — если поддержано.
