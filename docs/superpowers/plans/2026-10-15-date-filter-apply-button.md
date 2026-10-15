# «Найти» в фильтре по дате — только после правки. План

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** кнопка «Найти» в поповере фильтра по дате активна, только если поле «с» или «по» отличается (по дню) от значения при открытии поповера.

**Architecture:** правило живёт в чистом `nonisolated struct DateFilterDraft` (Models) — исходный диапазон, текущие поля, `applied`, `canApply`. `DateFilterPopover` держит его в `@State` и рисует поверх.

**Tech Stack:** Swift 6, SwiftUI (macOS), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-15-date-filter-apply-button-design.md`

## Global Constraints

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; модель помечается `nonisolated`, `Sendable`.
- Тесты — Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), файлы в `FB Loader/FB LoaderTests/`.
- Новые `.swift` в отслеживаемых директориях попадают в target сами, `project.pbxproj` не трогать.
- Сравнение по дню: обе стороны через `calendar.startOfDay(for:)` одного календаря.
- Работа в ветке `feature/date-filter-apply-button`, не в `main`.
- UI-коммит — только после ручной проверки Alexey. Мерж/пуш — только по явной команде.

## Review Focus

1. Перерисовка `BooksTableView` при открытом поповере повторно вызывает `DateFilterPopover.init` — `initial` не должен сдвигаться (держится `@State`; проверяется ручным тестом).
2. Кнопка «Сегодня» в календаре ставит `Date()` с часами в поле, где уже сегодняшняя полночь, — «Найти» остаётся неактивной (тест `sameDayDifferentTime`).
3. Исходное «по» с часами (`Date()` без фильтра), поле получает полночь того же дня из сетки — неактивна (тест `initialWithTimeVsMidnight`).
4. Enter при неактивной «Найти» не закрывает поповер (ручной тест).
5. Правка и возврат значения — неактивна (тест `changedAndReverted`).

---

### Task 0: Ветка и спеки

- [ ] **Step 1: создать ветку**

```bash
git checkout -b feature/date-filter-apply-button
```

- [ ] **Step 2: закоммитить спеки**

```bash
git add docs/superpowers/specs/2026-10-15-date-filter-apply-button-design.md \
        docs/superpowers/specs/2026-08-07-books-date-filter-design.md \
        docs/superpowers/plans/2026-10-15-date-filter-apply-button.md
git commit -m "docs: спека и план — «Найти» в фильтре дат только после правки"
```

### Task 1: `DateFilterDraft`

**Files:**
- Create: `FB Loader/FB Loader/Models/DateFilterDraft.swift`
- Test: `FB Loader/FB LoaderTests/DateFilterDraftTests.swift`

**Interfaces:**
- Consumes: `DateRangeFilter(from:to:)` (`Models/DateRangeFilter.swift`), `Equatable`.
- Produces: `DateFilterDraft(from: Date, to: Date, calendar: Calendar = .current)`, `var from: Date`, `var to: Date`, `let initial: DateRangeFilter`, `var applied: DateRangeFilter`, `var canApply: Bool`.

- [ ] **Step 1: падающий тест**

`FB Loader/FB LoaderTests/DateFilterDraftTests.swift`:

```swift
import Foundation
import Testing
@testable import FB_Loader

/// Календарь с фиксированным поясом — тесты не зависят от машины.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite("DateFilterDraft")
struct DateFilterDraftTests {
    private func draft(from: Date = at(2000, 1, 1),
                       to: Date = at(2026, 10, 15, 14, 30)) -> DateFilterDraft {
        DateFilterDraft(from: from, to: to, calendar: cal)
    }

    @Test("поля не тронуты — «Найти» неактивна")
    func untouched() {
        #expect(!draft().canApply)
    }

    @Test("исходное «по» с часами, поле — полночь того же дня")
    func initialWithTimeVsMidnight() {
        var d = draft()
        d.to = at(2026, 10, 15)
        #expect(!d.canApply)
    }

    @Test("тот же день с другим временем — не правка")
    func sameDayDifferentTime() {
        var d = draft(to: at(2026, 10, 15))
        d.to = at(2026, 10, 15, 23, 59)
        #expect(!d.canApply)
    }

    @Test("изменено «с»")
    func fromChanged() {
        var d = draft()
        d.from = at(2000, 1, 2)
        #expect(d.canApply)
    }

    @Test("изменено «по»")
    func toChanged() {
        var d = draft()
        d.to = at(2026, 10, 14)
        #expect(d.canApply)
    }

    @Test("изменено и возвращено — снова неактивна")
    func changedAndReverted() {
        var d = draft()
        d.from = at(2010, 5, 5)
        d.from = at(2000, 1, 1)
        #expect(!d.canApply)
    }

    @Test("applied приводит обе границы к полуночи")
    func appliedNormalized() {
        var d = draft()
        d.from = at(2013, 3, 1, 9, 15)
        #expect(d.applied == DateRangeFilter(from: at(2013, 3, 1), to: at(2026, 10, 15)))
    }
}
```

- [ ] **Step 2: убедиться, что не собирается**

```bash
xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" \
  -destination "platform=macOS" -only-testing:"FB LoaderTests/DateFilterDraftTests" test
```

Expected: FAIL — `cannot find 'DateFilterDraft' in scope`.

- [ ] **Step 3: реализация**

`FB Loader/FB Loader/Models/DateFilterDraft.swift`:

```swift
import Foundation

/// Поля поповера фильтра по дате. «Найти» активна, только когда поля
/// разошлись по дню с тем, что стояло в них при открытии поповера.
nonisolated struct DateFilterDraft: Equatable, Sendable {
    /// Поля при открытии, приведённые к полуночи.
    let initial: DateRangeFilter
    var from: Date
    var to: Date
    private let calendar: Calendar

    init(from: Date, to: Date, calendar: Calendar = .current) {
        self.from = from
        self.to = to
        self.calendar = calendar
        initial = Self.days(from: from, to: to, calendar: calendar)
    }

    /// Часы обнуляются так же, как у книг при импорте, — дальше
    /// сравниваются две полуночи.
    var applied: DateRangeFilter {
        Self.days(from: from, to: to, calendar: calendar)
    }

    var canApply: Bool { applied != initial }

    private static func days(from: Date, to: Date, calendar: Calendar) -> DateRangeFilter {
        DateRangeFilter(from: calendar.startOfDay(for: from),
                        to: calendar.startOfDay(for: to))
    }
}
```

- [ ] **Step 4: тесты зелёные**

Та же команда, что в Step 2. Expected: 7 тестов PASS.

- [ ] **Step 5: коммит** (backend — после зелёных тестов)

```bash
git add "FB Loader/FB Loader/Models/DateFilterDraft.swift" \
        "FB Loader/FB LoaderTests/DateFilterDraftTests.swift"
git commit -m "feat(DateFilter): DateFilterDraft — правило активности «Найти»"
```

### Task 2: `DateFilterPopover` на `DateFilterDraft`

**Files:**
- Modify: `FB Loader/FB Loader/UI/BooksTable/DateFilterPopover.swift` (весь тип: `@State from/to` → `draft`, кнопка «Найти», удалить `applied()`, doc-комментарий)

**Interfaces:**
- Consumes: `DateFilterDraft` из Task 1.
- Produces: внешний API поповера не меняется — `init(current: DateRangeFilter?, onApply: @escaping (DateRangeFilter?) -> Void)`.

- [ ] **Step 1: doc-комментарий типа** (строки 3–8)

```swift
/// Содержимое поповера, который открывается кликом по заголовку колонки
/// «Дата». Правка полей ни на что не влияет до нажатия «Найти»; сама
/// «Найти» активна, только когда поля разошлись с тем, что стояло в них
/// при открытии.
///
/// Календарь разворачивается внутри этого же окна, а не отдельным поповером
/// поверх него: вложенный поповер на macOS рисуется над родительским и
/// накрывает кнопки.
```

- [ ] **Step 2: состояние и `init`** (строки 16–25)

```swift
    /// В `@State`, а не `let`: `init` повторяется на каждой перерисовке
    /// таблицы, а исходное состояние должно остаться тем, что при открытии.
    @State private var draft: DateFilterDraft
    @State private var editing: Bound?

    init(current: DateRangeFilter?, onApply: @escaping (DateRangeFilter?) -> Void) {
        self.current = current
        self.onApply = onApply
        _draft = State(initialValue: DateFilterDraft(from: current?.from ?? Self.defaultFrom,
                                                     to: current?.to ?? Date()))
    }
```

- [ ] **Step 3: поля и кнопки в `body`** (строки 35–49)

```swift
            field("с", date: draft.from, bound: .from)
            field("по", date: draft.to, bound: .to)
```

```swift
                Button("Найти") { onApply(draft.applied) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canApply)
```

- [ ] **Step 4: календарь** (строка 94)

```swift
            MonthCalendar(selection: bound == .from ? $draft.from : $draft.to) {
```

- [ ] **Step 5: удалить приватный `applied()`** (строки 101–107 вместе с комментарием).

- [ ] **Step 6: полный прогон тестов**

```bash
xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" \
  -destination "platform=macOS" test
```

Expected: `** TEST SUCCEEDED **`, без новых предупреждений.

- [ ] **Step 7: ручная проверка Alexey** — чек-лист из спеки, раздел «Ручное UI-тестирование», плюс:
  - при открытом поповере поменять язык или что-то, что перерисует таблицу, — «Найти» не включается сама.

- [ ] **Step 8: коммит** — только после одобрения Alexey.

```bash
git add "FB Loader/FB Loader/UI/BooksTable/DateFilterPopover.swift"
git commit -m "feat(DateFilter): «Найти» активна только после правки дат"
```
