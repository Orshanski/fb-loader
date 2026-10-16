# Экспорт, часть 2: ExportSession, список ошибок, один запуск

Задача beads `fb-loader-tq1.13`. Дополняет §6 [основной спеки](2026-05-01-fb-loader-design.md)
и раздел «Чекбоксы и экспорт» [спеки поиска](2026-05-04-fuzzy-search-design.md).

## Цель

- Один сценарий выгрузки вместо двух копий `runExport` (`MainWindowView`, `SearchWindowView`) —
  тестируемый `ExportSession`.
- Окно прогресса показывает список ошибок «книга — причина», а не только «Ошибки: N».
- Новая выгрузка не стартует, пока жив runner предыдущей, даже если окно прогресса закрыто.
- Снятие галочки с выгруженной книги — O(1) на книгу, без пересчёта всего набора на тик.
- Точка подключения конвертера (FB2 → EPUB и т. п., `fb-loader-dsi`). Сам конвертер и выбор формата
  в UI — не в этой задаче; единственная реализация — копирование FB2 как есть.

## Компоненты и где живут

Префикс `FB Loader/FB Loader/`.

| файл | что |
|---|---|
| `Export/ExportSession.swift` (новый) | `ExportSession`, `ExportRequest`, `ExportOrigin` |
| `Export/ExportConverter.swift` (новый) | `ExportFormat`, `ExportConverter`, `PassthroughConverter`, `ExportConversionError`, `ExportConverters.make` |
| `UI/ExportFolderPanel.swift` (новый) | `ExportFolderPanel.choose(initial:)`; обе приватные копии `NSOpenPanel.selectedDirectory` удаляются |
| `Export/ExportPlanner.swift` | `ExportItem.archiveURL: URL` заполняется планировщиком; параметры `archivesRoot`, `format` в `plan`; лимит имени от формата |
| `Export/ExportFailure.swift` | `Stage.conversion` |
| `Export/ExportRunner.swift` | новая сигнатура (без `archivesRoot`, `library`; с `converter`, `onExported`); отмена внутри книги; комментарий 59–61 (про `.onChange(of: done)`) удаляется |
| `Export/ExportProgress.swift` | `Identifiable`; `succeeded` и `removingSucceeded` удаляются |
| `UI/ExportCleanup.swift` | удаляется (`onExportProgress`) |
| `UI/ExportProgressSheet.swift` | список ошибок; комментарий 22–30 (про финальный пересчёт) заменяется одной строкой: «Закрыть» после «Отмена» не ждёт runner |
| `AppState.swift` | `let exportSession = ExportSession(userPaths: UserPaths.shared, chooseFolder: ExportFolderPanel.choose)` вместо `var exportProgress` (`UserPaths.shared` — тот же экземпляр, что `userPaths`) |
| `UI/MainWindowView.swift` | `runExport`, `ProgressIdentifier`, `.onExportProgress` удаляются; sheet прогресса, `ExportAction`, `MainWindowActions.isAvailable` — через сессию; сессия передаётся в `SearchWindowView` |
| `UI/Search/SearchWindowView.swift` | параметр `exportSession`; `runExport`, `@State exportProgress`, `ProgressIdentifier`, `.onExportProgress` удаляются; sheet прогресса — через сессию |
| `UI/Search/SearchResultListView.swift` | параметр `exportSession`, передаётся в три блока |
| `UI/Search/SearchAuthorBlock.swift`, `SearchSeriesBlock.swift`, `SearchBooksBucketView.swift` | параметр `exportSession`; пункт меню учитывает `isBusy` |
| `UI/BooksTable/BooksTableView.swift` | `ExportAction.isAvailable` |
| `UI/BooksTable/BooksTableRepresentable.swift` | пункт меню учитывает `isAvailable` |

Выбор папки — замыкание, внедрённое в `ExportSession`: проверка «занято» должна покрывать и
время открытой панели, а `NSOpenPanel` в тесте не открыть.

## Контракт ExportSession

```swift
enum ExportOrigin { case main, search }

struct ExportRequest {
    let libids: Set<Int32>
    let library: Library
    let selectedAuthorID: Int32?
    let selectedSeriesID: Int32?
    let format: ExportFormat                     // сейчас всегда .fb2
    let origin: ExportOrigin
    let uncheck: @MainActor (Int32) -> Void
}

@MainActor @Observable
final class ExportSession {
    enum Phase: Equatable { case idle, choosingFolder, running }

    private(set) var phase: Phase                 // .idle
    private(set) var progress: ExportProgress?    // non-nil ⇔ окно прогресса показано
    private(set) var origin: ExportOrigin?        // окно, показывающее progress
    var isBusy: Bool { get }                      // phase != .idle

    typealias ChooseFolder = @MainActor (_ initial: URL?) async -> URL?
    typealias MakeConverter = (ExportFormat) -> any ExportConverter
    typealias Run = @MainActor (_ items: [ExportItem], _ exportRoot: URL, _ progress: ExportProgress,
                                _ converter: any ExportConverter,
                                _ onExported: @escaping @MainActor (Int32) -> Void) async -> Void

    init(userPaths: UserPaths, chooseFolder: @escaping ChooseFolder,
         makeConverter: @escaping MakeConverter = ExportConverters.make,
         run: @escaping Run = ExportRunner.run)

    /// nil — запуск не состоялся (занято, нечего выгружать, панель отменена).
    @discardableResult
    func start(_ request: ExportRequest) async -> Task<Void, Never>?
    func progress(for origin: ExportOrigin) -> ExportProgress?
    func closeProgress(origin: ExportOrigin)
}
```

Владелец — `AppState`, один экземпляр на приложение: одновременно идёт не больше одной выгрузки.

### `start`

1. `isBusy` → отказ (панель не открывается).
2. `libids` пуст или `userPaths.archivesDirectoryURL == nil` → отказ.
3. `phase = .choosingFolder`; `chooseFolder(начальная папка)`: `lastExportDirectoryURL`, если она
   есть и это существующая папка, иначе домашняя папка (`~`).
4. `nil` → `phase = .idle`, `lastExportDirectoryURL` не меняется, отказ.
5. Папка выбрана → `lastExportDirectoryURL = папка`; план — `ExportPlanner.plan` по полям `request`
   (не по текущему состоянию окна), `archivesRoot` из `userPaths`, `format: request.format`.
6. Новый `ExportProgress` заменяет прежний (если показан итог прошлой выгрузки — его окно
   закрывается), `origin = request.origin`, `phase = .running`; runner запускается в отдельной
   задаче с `items`, папкой, `progress`, `makeConverter(request.format)`, `request.uncheck`;
   `start` возвращает эту задачу, не дожидаясь её.
7. Runner вернулся → `phase = .idle`. `progress`/`origin` не трогаются: окно с итогом висит до «Закрыть».

После шага 5 ни сессия, ни задача runner'а не держат `Library` (`ExportItem` содержит `Book` и URL'ы).

### Окно прогресса и сессия

- `progress(for:)` — `progress`, если `origin` совпадает, иначе `nil`. Каждое окно (главное, поиск)
  показывает sheet прогресса, пока `progress(for: своё)` не `nil`; новая выгрузка — новый объект и
  новый sheet (`ExportProgress: Identifiable` по идентичности объекта).
- «Закрыть» → `closeProgress(origin:)`: `progress = nil`, `origin = nil`. `phase` не меняется:
  `isBusy` остаётся `true` до возврата runner'а.
- `closeProgress` с чужим `origin` — без эффекта.
- Панель папки — sheet к окну, где выбрали «Выгрузить»: пока она открыта,
  окно не принимает ввод, sheet поиска закрыть нельзя.
- Пока показан sheet прогресса, sheet поиска закрыть нельзя (модальность). Закрыть его можно, только
  когда `progress(for: .search) == nil`; runner при этом может быть жив — `uncheck` пишет в
  `SearchCoordinator` закрытого окна (без эффекта). При исчезновении окна поиска вызывается
  `closeProgress(origin: .search)` — страховка от устаревшего итога при следующем открытии поиска.
- Пересборка каталога в настройках во время `isBusy` не блокируется: после планирования `Library`
  держит только `AppState`, второй `Library` в памяти нет.

### `ExportFolderPanel.choose(initial:)`

- Каталоги, без файлов, с созданием папок; предзаполнение — `initial`.
- Окно — `NSApp.keyWindow`: панель как sheet к нему; нет ключевого окна — отдельным окном.
- Continuation возобновляется ровно один раз при любом `response`; не `.OK` → `nil`.
- Возвращает после `orderOut` панели — иначе sheet прогресса не покажется на том же окне.

## Список ошибок в UI

`ExportProgressSheet(progress:onClose:)` — сигнатура прежняя.

```
┌──────────────────────────────────────────────┐
│                  Выгрузка                    │
│  [██████████████░░░░░░░░░░░░░░░░]            │
│  37 / 120 — Война и мир                      │
│                                              │
│  Ошибки: 3                                   │
│  ┌────────────────────────────────────────┐  │
│  │ Анна Каренина                          │  │
│  │   Архив не найден — fb2-001.zip        │  │
│  │ Воскресение                            │  │
│  │   Книга не найдена в архиве fb2-002.zip│  │
│  │ Детство                                │▲ │
│  │   Нет места на диске                   │▼ │
│  └────────────────────────────────────────┘  │
│  Выгрузка прервана: Нет места на диске       │
│                                              │
│  [Отмена]                        [Закрыть]   │
└──────────────────────────────────────────────┘
```

- Блок есть, когда `failed` не пуст. Заголовок «Ошибки: N» (красный) остаётся. Плоский список со
  скроллом, без группировки и без кнопки копирования.
- Строка: название (одна строка, усечение посередине) + причина (`secondary`, одна строка).
- Порядок — порядок выгрузки, новые снизу; уже показанные строки не меняются (`failed` только
  дописывается); автопрокрутки нет.
- Высота растёт до ~6 строк, дальше скролл. Ширина — 360, как у прогресс-бара.
- Книга, на которой выгрузка прервалась, есть в списке; строка «Выгрузка прервана: …» — под ним.
- Тип `failed` (`[(title, error)]`) не меняется.
- Кнопки «Отмена»/«Закрыть» — правила активности прежние.

## Защита от двойного запуска

Признак — `exportSession.isBusy` (папка выбирается или runner жив), не наличие окна прогресса.

- ПКМ в таблице книг: сессия занята → единственный пункт «Выгрузка ещё идёт…», неактивный;
  иначе «Выгрузить отмеченные (N)», активен при N > 0. Таблица узнаёт занятость через `ExportAction`
  (`isAvailable` рядом с `perform`, задаёт `MainWindowView`), не через `BooksTableModel`.
- Окно поиска: три меню «Выгрузить отмеченные (N)» — те же правила; сессию блоки получают
  параметром: `MainWindowView` → `SearchWindowView` → `SearchResultListView` → блок.
- Блокировка общая для приложения: из поиска нельзя, пока жив runner из главного окна, и наоборот.
- Пункты меню главного окна (`MainWindowActions.isAvailable`) неактивны, пока показано окно прогресса
  главного окна или выбирается папка.
- `start` при `isBusy` — отказ (п. 1): контракт сессии, а не замена блокировки UI.

## Пересчёт галочек

- Runner после успешной записи книги вызывает `onExported(libid)` на main actor; для ошибок и
  отменённой книги не вызывает.
- `ExportRequest.uncheck` — удаление одного libid из набора галочек окна-источника
  (`state.checkedBookLibids` / `coord.checkedBookLibids`). Сессия передаёт его runner'у как
  `onExported`.
- Вызов не зависит от окна прогресса — финальный пересчёт после runner'а и подписка на
  `progress.done` удаляются.
- Галочка, поставленная вручную на уже выгруженную книгу во время выгрузки, остаётся.

## Конвертер и runner

```swift
nonisolated struct ExportFormat: Hashable, Sendable {
    let fileExtension: String                       // без точки
    static let fb2: ExportFormat                    // "fb2"
}

nonisolated protocol ExportConverter: Sendable {
    /// Обязан реагировать на отмену задачи (прервать работу, в т. ч. внешний процесс).
    @concurrent func convert(_ fb2: Data, book: Book) async throws -> Data
}

nonisolated struct PassthroughConverter: ExportConverter      // возвращает вход

nonisolated struct ExportConversionError: Error, Equatable {
    let reason: String           // по-русски, идёт в список ошибок
    let abortsExport: Bool       // повторится на каждой книге (напр. конвертер не установлен)
}

nonisolated enum ExportConverters {
    static func make(_ format: ExportFormat) -> any ExportConverter   // .fb2 → PassthroughConverter
}

enum ExportRunner {
    @MainActor
    static func run(items: [ExportItem], exportRoot: URL, progress: ExportProgress,
                    converter: any ExportConverter = PassthroughConverter(),
                    onExported: @escaping @MainActor (Int32) -> Void = { _ in }) async
}

nonisolated struct ExportItem { let book: Book; let archiveURL: URL; let destination: URL }

ExportPlanner.plan(libids:rootFolder:archivesRoot:selectedAuthorID:selectedSeriesID:format: = .fb2, in:)
```

- `@concurrent` в требовании протокола: при `SWIFT_APPROACHABLE_CONCURRENCY = YES` nonisolated async
  иначе исполняется на actor'е вызывающего (main).
- `ExportConverters.make` вызывается только с форматами, которые может запросить UI (сейчас `.fb2`);
  иной формат — ошибка программиста.
- `run` — единственная сигнатура runner'а, совпадает с `ExportSession.Run`.

### Планировщик

- `ExportItem.archiveURL = archivesRoot/<архив книги>.zip`.
- Расширение имени и суффиксы « (N)» — от `format.fileExtension` (`Название (2).<ext>`).
- Лимит имени файла: `limit(ext) = 255 − 11 − (1 + байты ext)` (11 — запас под « (NN…)»);
  для `fb2` — 240, как сейчас. Название режется по лимиту формата, имя папки — по 240.

### Книга в runner'е

- Вне main actor: чтение из `item.archiveURL` → `convert` → запись результата в `item.destination`
  (`.atomic`). Конвертер файлов не пишет: ошибки записи классифицируются как раньше (`.destination`).
- Ошибка `convert` → `ExportFailure(error, stage: .conversion)`: `ExportConversionError` → его
  `reason`/`abortsExport`; иная ошибка → «Не удалось преобразовать книгу», без прерывания. Попадает в
  тот же `failed` и тот же список в окне прогресса.
- Прогресс — по книгам: `done += 1` после каждой завершённой (успех или ошибка) книги.
- Отмена кооперативная: работа над книгой идёт в отменяемой задаче; `progress.cancelled = true`
  отменяет её. `CancellationError` — не ошибка: книга не попадает в `failed`, не записывается,
  `onExported` не вызывается, `done` не растёт, runner возвращается. `cancelled` проверяется и
  перед каждой книгой.

## Тесты

### `FB LoaderTests/ExportSessionTests.swift` (новый)

`UserPaths` на отдельном `UserDefaults(suiteName:)`; `chooseFolder` — стаб, записывающий вызовы и
возвращающий заданный URL/`nil`; `run` — стаб, записывающий аргументы и возвращающийся по сигналу
теста; конец runner'а — `await` задачи, которую вернул `start`.

| тест | проверяет |
|---|---|
| пустые `libids` | отказ, `chooseFolder` не вызван, `phase == .idle` |
| нет папки архивов | отказ, `chooseFolder` не вызван |
| начальная папка | `chooseFolder` получил `lastExportDirectoryURL`; без неё — `~` |
| недоступная запомненная папка | папки нет на диске → `chooseFolder` получил `~` |
| отмена панели | `phase == .idle`, `progress == nil`, `lastExportDirectoryURL` прежний, `run` не вызван |
| папка выбрана | `lastExportDirectoryURL` = выбранной; `phase == .running`; `progress(for: origin) != nil`, `progress(for: другой) == nil` |
| аргументы `run` | `exportRoot` = выбранной папке; у каждого item `archiveURL` = `archivesRoot` из `userPaths` + `<архив>.zip`; набор книг = `request.libids` |
| автор из запроса | папки в плане — по `request.selectedAuthorID`, а не по текущему состоянию окна |
| формат из запроса | `MakeConverter` получил `request.format`; имена в плане — с его расширением; `run` получил созданный конвертер |
| повторный `start` во время панели | отказ: `chooseFolder` вызван один раз |
| повторный `start` во время runner'а | отказ: `run` вызван один раз |
| закрыли окно, runner жив | `closeProgress` → `progress == nil`, `isBusy`, новый `start` — отказ; после возврата runner'а — `idle`, новый `start` открывает панель |
| `closeProgress` с чужим `origin` | `progress` не тронут |
| runner вернулся при открытом окне | `phase == .idle`, `progress` тот же |
| `start` при показанном итоге | после выбора папки — новый `ExportProgress` (не тот же объект), `origin` нового запроса |
| `uncheck` сквозной | `onExported`, полученный `run`, вызывает `request.uncheck`, в т. ч. после `closeProgress` |

### Остальное

Конвертер-стаб: возвращает заданные байты / бросает заданную ошибку / ждёт сигнала или отмены.

| тест | проверяет |
|---|---|
| `ExportRunnerTests`: `onExported` | вызван ровно для успешных libid в порядке выгрузки; не вызван для ошибок источника и назначения. Существующие проверки `progress.succeeded` переходят на записанные вызовы; helper `run` теряет `archivesRoot`/`library` |
| `ExportRunnerTests`: результат конвертера | на диске байты конвертера по пути `.epub`; `convert` получил FB2 из архива |
| `ExportRunnerTests`: ошибка конвертации | `ExportConversionError(reason: "X", abortsExport: false)` → в `failed` (`title`, `"X"`), следующая книга выгружена, `onExported` для упавшей не вызван |
| `ExportRunnerTests`: прерывающая ошибка конвертации | `abortsExport: true` → `abortReason == "X"`, дальше книги не трогаются |
| `ExportRunnerTests`: отмена между книгами | `cancelled = true` после книги 1 → `convert` вызван один раз, книга 2 не тронута |
| `ExportRunnerTests`: отмена во время конвертации | `cancelled = true`, пока `convert` ждёт → `convert` получил отмену, runner вернулся, `failed` пуст, файл не записан, `onExported` не вызван |
| `ExportPlannerTests`: формат | `Рубеж.epub`; коллизии `А.epub`, `А (2).epub`; `archiveURL` = `archivesRoot/<архив>.zip` |
| `ExportPlannerTests`: длинное название | 101 книга с одним длинным названием, формат `epub` → у сотой суффикс « (100)», каждое имя ≤ 255 байт |
| `ExportPlannerTests`: по умолчанию | без `format` — `.fb2`, имена как раньше; существующие вызовы получают `archivesRoot` |
| `ExportFailureTests`: `.conversion` | `ExportConversionError` → его поля; иная ошибка → «Не удалось преобразовать книгу», не прерывает |
| `BooksTableCoordinatorTests.contextMenu` | при `isAvailable == false` и N > 0 — один пункт «Выгрузка ещё идёт…», неактивен |

`ExportProgressTests.swift` удаляется вместе с `removingSucceeded`.

## Правки других спек

- Основная спека, §6 «Папка экспорта»: «При первом запуске или если запомнённый путь стал
  недоступен — предзаполнено `~/Downloads`» → «…— предзаполнена домашняя папка». Диалог — sheet окна,
  где выбрали «Выгрузить».
- Основная спека, §6 «Прогресс и отмена»: + «Под прогрессом — список ошибок со скроллом: название
  книги и причина. Одна выгрузка на приложение: пока предыдущая не завершилась, вместо
  „Выгрузить отмеченные“ — неактивный пункт „Выгрузка ещё идёт…“.»
- Спека поиска, «Изменения в существующих файлах → Экспорт»: «Реюзим `ExportPlanner.plan`/`ExportRunner.run`»
  → «через `ExportSession.start` с `origin: .search`, `selectedAuthorID/SeriesID: nil`».
- `2026-05-26-sidebar-tab-state-reset-design.md:70`: `exportProgress` → `exportSession`.
