# Sidebar Tab Selection — единая модель

## Контекст

`AppState` хранит четыре независимых поля сайдбара: `sidebarTab`,
`selectedAuthorID`, `selectedSeriesID`, `selectedGenreID`. Любая
комбинация валидна синтаксически, инварианта «правильный ID при
правильном табе» нет.

## Проблема

Переключаешь вкладку — оживает старый selected ID соседней секции,
а `selectedBookLibid` (preview книги) тащит за собой предыдущий
контекст.

## Цель

1. Сделать рассинхрон секции и ID грамматически невозможным.
2. Развести три сценария мутации по семантике сброса.

## Модель

Четыре поля схлопываются в одно:

```swift
enum SidebarSelection {
    case authors(Int32?)
    case series(Int32?)
    case genres(Int16?)
}

private(set) var sidebar: SidebarSelection = .authors(nil)
```

## Семантика

### Сценарий 1 — Picker (явный «чистый лист»)

| поле | значение |
|---|---|
| `sidebar` | `.<newCase>(nil)` |
| `selectedBookLibid` | `nil` |
| `sidebarFilter` | `""` |
| `checkedBookLibids` | `[]` |

### Сценарий 2 — deep-link из preview-chip

| поле | значение |
|---|---|
| `sidebar` | `.<thisCase>(id)` |
| `sidebarFilter` | имя сущности (`author.displayName` / `series.name`) |
| `checkedBookLibids` | `[]` |
| `selectedBookLibid` | сохраняется |

Прицельный фильтр работает как scroll-to-selection — список в
сайдбаре сжимается до 1-2 элементов. Применяется одинаково для
cross-section и same-section.

### Сценарий 3 — клик в списке сайдбара

| поле | значение |
|---|---|
| `sidebar` | `.<thisCase>(id)` |
| `selectedBookLibid` | `nil` |
| `sidebarFilter` | сохраняется |
| `checkedBookLibids` | `[]` |

### Не трогается ни в одном сценарии

`languageFilter`, `exportSession`, `userPaths`, `stage`.

## API в AppState

```swift
private(set) var sidebar: SidebarSelection = .authors(nil)

func selectSection(_ section: SidebarSelection)
func selectAuthor(_ id: Int32?, deepLinkName: String? = nil)
func selectSeries(_ id: Int32?, deepLinkName: String? = nil)
func selectGenre(_ id: Int16?)
```

- `selectSection` — Сценарий 1. No-op только если `section == sidebar`
  (case + associated value совпадают). При любом другом значении —
  полный сброс из таблицы Сценария 1.
- `selectAuthor/Series` с `deepLinkName != nil` — Сценарий 2.
  Применяется всегда, даже если ID уже равен текущему: фильтр
  перезаписывается, `checkedBookLibids` обнуляется (re-click chip
  идемпотентно прицеливается).
- `selectAuthor/Series` с `deepLinkName == nil` и `selectGenre` —
  Сценарий 3. No-op если `sidebar == .<thisCase>(id)`.

`selectGenre` без параметра `deepLinkName` — жанрового chip в
preview нет, Сценарий 2 для жанров недостижим.

`reset()` обновляется так, чтобы выставлять `sidebar = .authors(nil)`.

## Touch-points

- **`AppState.swift`** — enum `SidebarSelection`, замена четырёх
  полей на одно, четыре метода, апдейт `reset()`.
- **`UI/LeftSidebarView.swift`** — Picker через
  `Binding(get: { case-метка из state.sidebar },
          set: { state.selectSection(.<case>(nil)) })`.
  Дочерние list-views получают `Binding<Int32?>` /
  `Binding<Int16?>`: get — pattern-match из `state.sidebar`,
  set — `state.selectAuthor($0)` / `selectSeries($0)` /
  `selectGenre($0)` (без `deepLinkName`).
- **`UI/MainWindowView.swift`** — `onSelectAuthor` /
  `onSelectSeries` резолвят имя через `library` и зовут
  `state.selectAuthor(aid, deepLinkName: library.authorByID[aid]?.displayName)`
  / `state.selectSeries(sid, deepLinkName: library.seriesByID[sid]?.name)`.
  `runExport` достаёт `selectedAuthorID` / `selectedSeriesID`
  через pattern-match по `state.sidebar`.
- **`UI/BooksTable/BooksTableView.swift`** — `visibleBooks` и
  `breadcrumbLabel` на pattern-match.

## Что НЕ меняем

- `AuthorsListView`, `SeriesListView`, `GenresListView`,
  `FilteredSidebarList`, `LazyListTable`, `BookDetailView`,
  `ExportPlanner` — сигнатуры и поведение те же.
- `languageFilter`, экспорт, кнопка лупы.

## Тесты

Файл `FB Loader/FB LoaderTests/AppStateTests.swift`,
`@MainActor @Suite struct AppStateTests`.

1. Дефолт: `sidebar == .authors(nil)`, остальное — дефолты.
2. `selectSection(.series(nil))` из `(.authors, sidebarFilter="x",
   checkedBookLibids=[1], selectedBookLibid=Y)` → секция меняется,
   три per-tab поля обнуляются, `languageFilter` сохраняется.
3. `selectSection(.authors(10))` из `(.authors(10), filter="x",
   checked=[1], book=Y, languageFilter="en")` — полный no-op, все
   поля сохраняются.
3a. `selectSection(.authors(nil))` из `(.authors(10), filter="x",
    checked=[1], book=Y)` — сценарий 1: `.authors(nil)`,
    `filter == ""`, `checked == []`, `book == nil`.
4. `selectAuthor(42)` (без имени) из `(.authors(10), filter="x",
   checked=[1], book=Y)` → `.authors(42)`, `book == nil`,
   `checked == []`, `filter == "x"` сохраняется.
4a. `selectAuthor(10)` (без имени) из `(.authors(10), filter="x",
    checked=[1], book=Y)` — same-ID no-op: `.authors(10)`,
    `book == Y`, `checked == [1]`, `filter == "x"` сохраняются.
    Защита от повторного клика по уже выбранной строке в
    `LazyListTable`.
5. `selectAuthor(42, deepLinkName: "Иванов")` из `(.series(X),
   filter="x", checked=[1], book=Y)` → `.authors(42)`,
   `filter == "Иванов"`, `checked == []`, `book == Y` сохраняется.
6. `selectAuthor(42, deepLinkName: "Иванов")` same-section из
   `(.authors(10), filter="Толстой", checked=[1], book=Y)` →
   `.authors(42)`, `filter == "Иванов"` (старый затёрт),
   `checked == []`, `book == Y` сохраняется.
6a. `selectAuthor(10, deepLinkName: "Иванов")` при том же ID из
    `(.authors(10), filter="Толстой", checked=[1], book=Y)` →
    `.authors(10)`, `filter == "Иванов"`, `checked == []`,
    `book == Y` сохраняется. Re-click chip того же автора —
    идемпотентный прицел.
7. `selectSeries(_, deepLinkName:)` симметричен (5).
8. `selectGenre(7)` (всегда без имени) из `(.series(X), book=Y,
   checked=[1], filter="x")` → `.genres(7)`, `book == nil`,
   `checked == []`, `filter == "x"`.
9. `selectAuthor(nil)` (без имени) из `.authors(10)` →
   `.authors(nil)`, `book == nil`, `checked == []`, `filter`
   сохраняется.
10. `reset()` — `sidebar == .authors(nil)`, остальные поля —
    дефолты.

## Ручное UI-тестирование

- **Баг.** Серии → серия → книга → Picker «Авторы». Сайдбар чистый,
  фильтр пустой, средняя панель пустая, preview гасится.
- **Скролл.** Авторы → Серии → Авторы. Скролл сайдбара идёт с
  начала (разные view-tree).
- **Deep-link same-section.** В preview книги chip соавтора. Picker
  на Авторах, фильтр = имя соавтора, в списке он подсвечен,
  preview сохранён, в средней панели книга подсвечена среди книг
  соавтора.
- **Deep-link cross-section.** В preview книги chip серии. Picker
  на Сериях, фильтр = имя серии, в списке серия подсвечена,
  preview сохранён, в средней панели книга подсвечена.
- **Клик в списке сайдбара.** В Авторах кликнуть нового автора.
  Preview гасится, фильтр сохраняется, галочки сбрасываются.
