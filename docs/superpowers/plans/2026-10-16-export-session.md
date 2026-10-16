# План: экспорт, часть 2 (ExportSession, список ошибок, один запуск)

Спека: [2026-10-16-export-session-design.md](../specs/2026-10-16-export-session-design.md).
Beads: `fb-loader-tq1.13`. Ветка от `main`. В каждой задаче сначала тесты, потом реализация.
После каждой задачи весь набор тестов зелёный, предупреждений нет (кроме трёх известных `appintentsmetadataprocessor`).
Префикс путей — `FB Loader/`.

## 1. Типы конвертера и стадия `.conversion`

- Файлы: `FB Loader/Export/ExportConverter.swift` (новый), `FB Loader/Export/ExportFailure.swift`,
  `FB LoaderTests/ExportRunnerTests.swift` (suite `ExportFailure`).
- Типы: `ExportFormat`, `ExportConverter` (`@concurrent convert`), `PassthroughConverter`,
  `ExportConversionError`, `ExportConverters.make`, `ExportFailure.Stage.conversion` — спека,
  «Конвертер и runner» и «Книга в runner'е».
- Тесты: `.conversion`. `ExportConversionError` даёт свои `reason`/`abortsExport`, любая другая
  ошибка — «Не удалось преобразовать книгу», без прерывания.
- Готово: типы есть, нигде пока не используются, тесты зелёные.

## 2. Планировщик: `archivesRoot`, формат, лимит

- Файлы: `FB Loader/Export/ExportPlanner.swift`; вызовы `plan` в `UI/MainWindowView.swift`,
  `UI/Search/SearchWindowView.swift`, `FB LoaderTests/ExportPlannerTests.swift`,
  `FB LoaderTests/ExportRunnerTests.swift` (helper).
- Сигнатуры: `ExportItem.archiveURL: URL`, `plan(…archivesRoot:…format:…)` и лимит `limit(ext)` —
  спека, «Планировщик».
- Тесты (`ExportPlannerTests`):
  - формат (`.epub`, коллизии, `archiveURL`);
  - длинное название × 101 книга (суффикс « (100)», ≤ 255 байт);
  - по умолчанию `.fb2`, существующие имена не меняются.
- Готово: оба окна передают `archivesRoot` и `.fb2`, поведение выгрузки прежнее.

## 3. Runner: новая сигнатура, конвертер, `onExported`, отмена

- Файлы: `FB Loader/Export/ExportRunner.swift`, вызовы `run` в обоих окнах,
  `FB LoaderTests/ExportRunnerTests.swift`.
- Сигнатура `ExportRunner.run` — спека, «Конвертер и runner». Поведение — «Книга в runner'е» и
  «Пересчёт галочек». Комментарий 59–61 удалить.
- Временно: `progress.succeeded` по-прежнему заполняется — его ещё читают окна. Удаляется в задаче 5.
- Тесты (`ExportRunnerTests`):
  - `onExported` вызывается только для успешных книг, в порядке выгрузки;
  - результат конвертера пишется по пути `.epub`;
  - ошибка конвертации: обычная и прерывающая;
  - отмена между книгами;
  - отмена во время конвертации: стаб получает отмену, `failed` пуст, файла нет;
  - существующие тесты переписать на проверку записанных вызовов `onExported` (helper без
    `archivesRoot`/`library`).
- Готово: runner не принимает `Library`, а окна выгружают как раньше.

## 4. `ExportFolderPanel` и `ExportSession`

- Файлы: `FB Loader/UI/ExportFolderPanel.swift` (новый), `FB Loader/Export/ExportSession.swift`
  (новый), `FB LoaderTests/ExportSessionTests.swift` (новый).
- Контракт — спека, «Контракт ExportSession» (все подразделы).
- Тесты: вся таблица `ExportSessionTests` из спеки. Стабы `chooseFolder`/`run`, отдельный suite
  `UserDefaults`. Для «недоступной запомненной папки» — путь, которого нет на диске.
- `ExportFolderPanel` тестами не покрывается (AppKit); проверяется вручную в задаче 5.
- Готово: сессия собирается и проходит тесты; в UI её пока нет.

## 5. Перевод UI на сессию, удаление старого пути

- Файлы:
  - `AppState.swift`;
  - `UI/MainWindowView.swift`;
  - `UI/Search/SearchWindowView.swift`, `SearchResultListView.swift`, `SearchAuthorBlock.swift`,
    `SearchSeriesBlock.swift`, `SearchBooksBucketView.swift`;
  - `UI/BooksTable/BooksTableView.swift` (`ExportAction.isAvailable`),
    `UI/BooksTable/BooksTableRepresentable.swift`;
  - `Export/ExportProgress.swift` (`Identifiable`; удалить `succeeded`, `removingSucceeded`);
  - удалить `UI/ExportCleanup.swift` и `FB LoaderTests/ExportProgressTests.swift`;
  - `FB LoaderTests/BooksTableCoordinatorTests.swift`.
- Правила — спека: «Окно прогресса и сессия», «Защита от двойного запуска», «Пересчёт галочек»,
  таблица «Компоненты и где живут» (включая комментарий в `ExportProgressSheet` 22–30).
- Тесты: `contextMenu` — при `isAvailable == false` один неактивный пункт «Выгрузка ещё идёт…».
- Готово:
  - grep не находит `runExport`, `exportProgress`, `removingSucceeded`, `onExportProgress`,
    `ProgressIdentifier`, `selectedDirectory`;
  - в обоих окнах выгрузка идёт через `exportSession.start`.

## 6. Список ошибок в окне прогресса

- Файл: `UI/ExportProgressSheet.swift`.
- Вид и правила — спека, «Список ошибок в UI».
- Тестов нет (вью); проверка вручную.
- Готово: список виден при `failed` не пусто, скроллится после ~6 строк.

## 7. Правки других спек

- Файлы: `docs/superpowers/specs/2026-05-01-fb-loader-design.md` (§6),
  `2026-05-04-fuzzy-search-design.md`, `2026-05-26-sidebar-tab-state-reset-design.md:70`.
- Текст правок — спека, «Правки других спек».
- Готово: формулировки внесены дословно.

## Ручная проверка (Alexey, до мержа)

- Главное окно и поиск:
  - панель папки — sheet окна;
  - первая выгрузка открывается в `~`, следующая — в последней папке;
  - после выгрузки галочки снимаются.
- Ошибки: отсутствующий архив → строки «Название — причина», скролл при большом числе.
- «Отмена» → «Закрыть», пока дописывается книга: в меню неактивный «Выгрузка ещё идёт…»; после
  окончания — снова «Выгрузить отмеченные (N)».
