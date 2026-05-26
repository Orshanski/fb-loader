# Снятие галочки с книги после её выгрузки — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Цель:** Снимать галочку с книги в списке сразу после её успешной выгрузки, чтобы пользователь не выгружал повторно уже скачанное и видел, что именно уже скачано. Покрывает оба окна: главное и окно поиска.

**Архитектура:** `ExportRunner` пишет libid каждой успешно выгруженной книги в новое поле `ExportProgress.succeeded: Set<Int32>`. Родительская вьюха (главное окно и окно поиска) делает две вещи:

1. Подписывается на изменения `progress.done` через `.onChange` и инкрементально пересчитывает `checkedBookLibids = progress.subtractingSucceeded(from: checkedBookLibids)` — для визуального эффекта «тающего списка» во время выгрузки.
2. После завершения `await ExportRunner.run(...)` делает финальный пересчёт того же выражения — гарантия, что последняя «дописавшаяся» книга, чья запись в `succeeded` могла случиться после клика «Закрыть»/«Отмена», тоже снимется с галочки.

API `ExportRunner` НЕ меняется (никаких callback'ов). Метод возвращает новый `Set`, а не мутирует `inout` — это требование `@Environment(AppState.self)`, через который доступ к `AppState` get-only.

**Бизнес-поведение:**
- Книга выгружена успешно → её галочка снимается немедленно, в момент завершения этой книги (пока выгрузка остальных продолжается).
- Книга выгружена с ошибкой → её галочка остаётся, пользователь может повторить выгрузку.
- Пользователь жмёт «Отмена» в окне прогресса → книги, которые успели выгрузиться до отмены (включая ту, что в момент клика была in-flight), теряют галочку. Книги, которые не успели, — остаются отмеченными.
- Существующий баг «при отмене кнопка Закрыть disabled навсегда» чинится в этой же задаче.

**Tech Stack:** Swift 6 + SwiftUI, Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Все типы MainActor-isolated по умолчанию (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). `ExportProgress` — `@MainActor @Observable`.

**Issue:** `fb-loader-ewm` (заклеймён). **Ветка:** `fix/clear-checkmark-after-export-fb-loader-ewm` (создана).

---

## Структура изменений

- **Modify:** `FB Loader/FB Loader/Export/ExportProgress.swift` — добавить `succeeded: Set<Int32>` и метод `subtractingSucceeded(from:)`.
- **Modify:** `FB Loader/FB Loader/Export/ExportRunner.swift` — сбрасывать `succeeded` в init-блоке, писать `libid` в else-ветке.
- **Modify:** `FB Loader/FB Loader/UI/ExportProgressSheet.swift` — разрешить «Закрыть» при отмене.
- **Modify:** `FB Loader/FB Loader/UI/MainWindowView.swift` — `.onChange(of: state.exportProgress?.done)` + финальный пересчёт после `await ExportRunner.run`.
- **Modify:** `FB Loader/FB Loader/UI/Search/SearchWindowView.swift` — то же для `coord.checkedBookLibids`.
- **Create:** `FB Loader/FB LoaderTests/ExportProgressTests.swift` — юнит-тесты на `subtractingSucceeded(from:)`.

Тесты лежат плоско в `FB LoaderTests/` — текущая конвенция проекта (см. `ExportPlannerTests.swift`, `LibraryBinaryCodecTests.swift` и т.д.).

---

### Task 1: Failing-тест на `ExportProgress.subtractingSucceeded(from:)`

**Files:**
- Create: `FB Loader/FB LoaderTests/ExportProgressTests.swift`

- [ ] **Step 1: Написать тест-сьют**

```swift
import Testing
import Foundation
@testable import FB_Loader

@Suite("ExportProgress.subtractingSucceeded")
@MainActor
struct ExportProgressTests {

    @Test("снимает только успешно выгруженные книги")
    func removesOnlySucceeded() {
        let p = ExportProgress()
        p.succeeded = [1, 3]
        let result = p.subtractingSucceeded(from: [1, 2, 3, 4])
        #expect(result == [2, 4])
    }

    @Test("книги с ошибкой выгрузки остаются отмеченными")
    func keepsFailedChecked() {
        let p = ExportProgress()
        p.succeeded = [1]
        p.failed = [(title: "book 2", error: "not found")]
        let result = p.subtractingSucceeded(from: [1, 2])
        #expect(result == [2])
    }

    @Test("пустой succeeded — набор не меняется")
    func emptySucceededLeavesChecksUntouched() {
        let p = ExportProgress()
        let result = p.subtractingSucceeded(from: [1, 2, 3])
        #expect(result == [1, 2, 3])
    }

    @Test("libid'ы, отсутствующие в наборе, игнорируются")
    func orphanSucceededIgnored() {
        let p = ExportProgress()
        p.succeeded = [99]
        let result = p.subtractingSucceeded(from: [1, 2])
        #expect(result == [1, 2])
    }
}
```

`@MainActor` на сьюте необходим: `ExportProgress` объявлен `@MainActor`, доступ к его свойствам из тестовых функций требует main-actor isolation.

- [ ] **Step 2: Прогнать — убедиться, что тест не компилируется**

Run:
```
xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build-for-testing
```
Expected: BUILD FAILED — `value of type 'ExportProgress' has no member 'succeeded'` и `... has no member 'subtractingSucceeded'`.

---

### Task 2: Добавить `succeeded` и `subtractingSucceeded(from:)` в `ExportProgress`

**Files:**
- Modify: `FB Loader/FB Loader/Export/ExportProgress.swift`

- [ ] **Step 1: Расширить `ExportProgress`**

Полностью переписать файл:

```swift
import Foundation
import Observation

/// Mutated and read only on the main actor (matches `ExportRunner.run`).
/// `@MainActor` makes Swift 6 strict-concurrency happy.
@MainActor
@Observable
final class ExportProgress {
    var total: Int = 0
    var done: Int = 0
    var currentTitle: String = ""
    var cancelled: Bool = false
    var failed: [(title: String, error: String)] = []
    /// `libid` каждой книги, успешно записанной на диск. Растёт по мере
    /// выгрузки; читается родительской вьюхой через
    /// `subtractingSucceeded(from:)` для инкрементального снятия галочек.
    var succeeded: Set<Int32> = []

    /// Возвращает новый набор: переданный `set` минус libid'ы из `succeeded`.
    /// Возвращает значение (не `inout`), потому что родительская вьюха
    /// держит `checkedBookLibids` в `AppState`/`SearchCoordinator`, доступ к
    /// которым через `@Environment`/`@State` get-only и не позволяет
    /// передать поле как `inout`-параметр.
    func subtractingSucceeded(from set: Set<Int32>) -> Set<Int32> {
        set.subtracting(succeeded)
    }
}
```

- [ ] **Step 2: Прогнать тест Task 1**

Run:
```
xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/ExportProgressTests"
```
Expected: 4 теста PASS.

Если синтаксис `-only-testing:` для Swift Testing не сработает в текущей версии Xcode — прогнать без фильтра (`test`), отфильтровать сьют по выводу. Имя бандла (`FB LoaderTests`) содержит пробел и экранируется кавычками выше.

---

### Task 3: Писать libid в `succeeded` при успехе и сбрасывать в начале `run`

**Files:**
- Modify: `FB Loader/FB Loader/Export/ExportRunner.swift`

Изменения:
- В init-блоке (строки 13-17) добавить `progress.succeeded = []` — симметрично с `progress.failed = []`. Защита на случай переиспользования `ExportProgress` (сейчас не используется, но будет страховкой при будущем рефакторинге).
- В блоке записи результата (строки 44-45) добавить else-ветку с `progress.succeeded.insert(book.libid)` — **до** `progress.done += 1` (инвариант: вьюха через `.onChange(of: progress.done)` читает `succeeded`, поэтому `succeeded` должен быть актуален к моменту инкремента `done`).

- [ ] **Step 1: Полная замена тела `run`**

```swift
import Foundation

enum ExportRunner {
    /// Runs entirely on the main actor so `progress` can be mutated without hops.
    /// Heavy I/O (zip read + file write) is dispatched off-main via `Task.detached`.
    /// One detached task per book — sequential to keep disk/network thrashing low and
    /// to match freeLib's behaviour (exportthread.cpp processes books one by one).
    @MainActor
    static func run(items: [ExportItem],
                    archivesRoot: URL,
                    library: Library,
                    progress: ExportProgress) async {
        progress.total = items.count
        progress.done = 0
        progress.currentTitle = ""
        progress.cancelled = false
        progress.failed = []
        progress.succeeded = []

        for item in items {
            if progress.cancelled { return }
            progress.currentTitle = item.book.title

            let book = item.book
            let dest = item.destination
            let archives = archivesRoot
            let archiveName = library.archives[Int(book.archiveIndex)] + ".zip"

            // Off-main: open zip, extract bytes, write to disk.
            // Returns nil on success, or the error message on failure.
            let errorMessage: String? = await Task.detached(priority: .utility) { () -> String? in
                let archiveURL = archives.appendingPathComponent(archiveName)
                do {
                    let data = try ZipFB2Reader.readFB2(libid: book.libid, archiveURL: archiveURL)
                    try FileManager.default.createDirectory(
                        at: dest.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    try data.write(to: dest, options: .atomic)
                    return nil
                } catch {
                    return "\(error)"
                }
            }.value

            // Invariant: succeeded/failed обновляются ДО `done += 1`,
            // чтобы `.onChange(of: progress.done)` в родительской вьюхе
            // видел консистентное состояние при срабатывании.
            if let msg = errorMessage {
                progress.failed.append((book.title, msg))
            } else {
                progress.succeeded.insert(book.libid)
            }
            progress.done += 1
        }
    }
}
```

- [ ] **Step 2: Прогнать весь test-suite — убедиться, что ничего не сломалось**

Run:
```
xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test
```
Expected: все тесты зелёные (4 новых + старые).

Запись `succeeded.insert(book.libid)` в успешной ветке покрывается ручным сценарием 1 в Task 7 — для юнит-теста нужна zip-фикстура с реальным FB2 внутри, которой в проекте нет.

---

### Task 4: Разрешить закрытие окна прогресса при отмене

**Files:**
- Modify: `FB Loader/FB Loader/UI/ExportProgressSheet.swift`

Без этого фикса при отмене окно прогресса не закрыть — кнопка «Закрыть» disabled навсегда. С учётом фикса в Task 5/6 (финальный пересчёт после `await run`) галочки снимутся даже без закрытия окна, но пользователь не должен застревать в окне.

- [ ] **Step 1: Расширить условие disabled у обеих кнопок**

Заменить блок (строки 18-25):

```swift
HStack {
    Button("Отмена") { progress.cancelled = true }
        .disabled(progress.done >= progress.total)
    Spacer()
    Button("Закрыть") { onClose() }
        .disabled(progress.total > 0 && progress.done < progress.total)
        .keyboardShortcut(.defaultAction)
}.frame(width: 360)
```

На:

```swift
HStack {
    Button("Отмена") { progress.cancelled = true }
        .disabled(progress.done >= progress.total || progress.cancelled)
    Spacer()
    Button("Закрыть") { onClose() }
        .disabled(progress.total > 0 && progress.done < progress.total && !progress.cancelled)
        .keyboardShortcut(.defaultAction)
}.frame(width: 360)
```

`|| progress.cancelled` у «Отмена» — чтобы после нажатия кнопка сразу гасла. `&& !progress.cancelled` у «Закрыть» — чтобы при отмене кнопка стала активной и пользователь мог закрыть окно.

- [ ] **Step 2: Build**

Run:
```
xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build
```
Expected: BUILD SUCCEEDED.

---

### Task 5: Подписаться на `progress.done` и финальный пересчёт в `MainWindowView`

**Files:**
- Modify: `FB Loader/FB Loader/UI/MainWindowView.swift`

Два места изменений:
- `.onChange(of: state.exportProgress?.done)` — инкрементальный пересчёт по факту каждой книги (UX «тающий список»).
- В `runExport()` после `await ExportRunner.run(...)` — финальный пересчёт. Если пользователь после «Отмена» сразу нажал «Закрыть», `state.exportProgress = nil` обнулится, sheet закроется, а run-loop в этот момент ещё ждёт `await` на detached-таске последней книги. Когда detached вернётся, libid допишется в `progress.succeeded`, но `.onChange` уже не сработает (биндинг nil). Финальный пересчёт после `await run` берёт уже-полное `succeeded` и снимает оставшееся.

- [ ] **Step 1: Добавить `.onChange` к корневой `HSplitView`**

Найти блок с `.sheet`-модификатором (строки 73-82). Сразу после него (после закрывающей фигурной скобки `.sheet`-блока) добавить:

```swift
.onChange(of: state.exportProgress?.done) { _, _ in
    // Инкрементальное снятие галочки по факту каждой выгруженной книги.
    // Выражение возвращает новый Set; финальный пересчёт после
    // `await ExportRunner.run` в runExport() закрывает race с in-flight
    // книгой, чья запись в succeeded могла случиться после клика «Закрыть».
    if let progress = state.exportProgress {
        state.checkedBookLibids = progress.subtractingSucceeded(
            from: state.checkedBookLibids)
    }
}
```

- [ ] **Step 2: Добавить финальный пересчёт в `runExport()`**

Заменить блок (строки 110-113):

```swift
Task {
    await ExportRunner.run(items: items, archivesRoot: archives,
                           library: library, progress: progress)
}
```

На:

```swift
Task {
    await ExportRunner.run(items: items, archivesRoot: archives,
                           library: library, progress: progress)
    // Финальный пересчёт. Если sheet закрыли после «Отмена», detached
    // последней книги мог дописаться уже после `state.exportProgress = nil` —
    // `.onChange` тогда не срабатывает (биндинг nil). Здесь берём
    // полное `progress.succeeded` и снимаем оставшееся.
    state.checkedBookLibids = progress.subtractingSucceeded(
        from: state.checkedBookLibids)
}
```

- [ ] **Step 3: Build**

Run:
```
xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build
```
Expected: BUILD SUCCEEDED.

---

### Task 6: Подписаться на `progress.done` и финальный пересчёт в `SearchWindowView`

**Files:**
- Modify: `FB Loader/FB Loader/UI/Search/SearchWindowView.swift`

Симметричное изменение для окна поиска: `coord` (а не `state`), локальный `exportProgress: @State` (а не `state.exportProgress`).

- [ ] **Step 1: Добавить `.onChange` после `.sheet`**

Сразу после блока `.sheet` (строки 52-58, после закрывающей фигурной скобки):

```swift
.onChange(of: exportProgress?.done) { _, _ in
    // Инкрементальное снятие галочки по факту каждой выгруженной книги.
    if let progress = exportProgress {
        coord.checkedBookLibids = progress.subtractingSucceeded(
            from: coord.checkedBookLibids)
    }
}
```

- [ ] **Step 2: Добавить финальный пересчёт в `runExport()`**

Заменить блок (строки 170-173):

```swift
Task {
    await ExportRunner.run(items: items, archivesRoot: archives,
                           library: library, progress: progress)
}
```

На:

```swift
Task {
    await ExportRunner.run(items: items, archivesRoot: archives,
                           library: library, progress: progress)
    // Финальный пересчёт (см. MainWindowView.runExport для деталей).
    coord.checkedBookLibids = progress.subtractingSucceeded(
        from: coord.checkedBookLibids)
}
```

- [ ] **Step 3: Build**

Run:
```
xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build
```
Expected: BUILD SUCCEEDED.

---

### Task 7: Полный прогон тестов и ручное тестирование

- [ ] **Step 1: Прогнать весь test-suite**

Run:
```
xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test
```
Expected: все тесты зелёные.

- [ ] **Step 2: Сообщить Alexey о готовности к ручному тестированию**

UI-таска, поэтому коммит — только после явного OK Alexey. Сценарии:

1. **Главное окно, нормальная выгрузка.** Отметить 3 книги, нажать «Выгрузить», выбрать папку, дождаться завершения, нажать «Закрыть». Все три галочки должны быть сняты.
2. **Главное окно, ошибка выгрузки.** Если есть возможность создать книгу с битым архивом — повторить. Книга с ошибкой остаётся отмеченной, остальные — нет.
3. **Главное окно, отмена.** Отметить 5 книг, запустить выгрузку, нажать «Отмена». Кнопка «Закрыть» должна стать активной. Нажать «Закрыть». Книги, успевшие выгрузиться до отмены (включая ту, что была in-flight в момент клика), — без галочки. Не успевшие — с галочкой.
4. **Окно поиска.** Открыть поиск, отметить книги, нажать «Выгрузить отмеченные». Повторить сценарии 1–3.

---

### Task 8: Спек-ревью кода

CLAUDE.md проекта требует двух ревью кода — спек-ревью (соответствие коду спеке/плану) и код-ревью (качество кода).

- [ ] **Step 1: Запустить ревьюера на соответствие кода плану**

Передать ревьюеру: путь к этому плану, путь к diff'у изменений (`git diff main`). Показать Alexey ВСЕ findings без фильтрации.

- [ ] **Step 2: Зафиксировать findings, отдать решение Alexey**

---

### Task 9: Код-ревью

- [ ] **Step 1: Запустить ревьюера на качество кода**

Показать Alexey ВСЕ findings.

- [ ] **Step 2: Исправить findings по согласованию с Alexey**

- [ ] **Step 3: Повторный прогон тестов**

Run:
```
xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test
```
Expected: все тесты зелёные.

---

### Task 10: Коммит, закрытие issue, follow-up

- [ ] **Step 1: Дождаться явного OK от Alexey по ручному тестированию.**

- [ ] **Step 2: Коммит**

```
git add "FB Loader/FB Loader/Export/ExportProgress.swift" \
        "FB Loader/FB Loader/Export/ExportRunner.swift" \
        "FB Loader/FB Loader/UI/ExportProgressSheet.swift" \
        "FB Loader/FB Loader/UI/MainWindowView.swift" \
        "FB Loader/FB Loader/UI/Search/SearchWindowView.swift" \
        "FB Loader/FB LoaderTests/ExportProgressTests.swift" \
        "docs/superpowers/plans/2026-05-25-clear-checkmark-after-export.md"
git commit -m "fix: clear book checkmarks after successful export (fb-loader-ewm)"
```

- [ ] **Step 3: Завести follow-up bd issue про визуальный индикатор для книг, скачанных в прошлых сессиях**

Issue fb-loader-ewm требует, чтобы «пользователь видел, что именно уже скачано». Этот план покрывает книги, выгружаемые в текущей сессии. Книги, скачанные в прошлых сессиях, неотличимы от ещё не скачанных — нужна отдельная фича (например, проверка `FileManager.fileExists` для destination-path):

```
bd create --title="Визуальный индикатор для книг, уже скачанных в прошлых сессиях" --description="После закрытия приложения список галочек сбрасывается, и юзер не видит, какие книги уже у него на диске. Нужен визуальный маркер (отдельная от галочки иконка) для книг, для которых destination-path уже существует. Зависит от знания папки экспорта — возможно, хранить per-author/per-series в UserPaths и проверять при отрисовке BookRow." --type=feature --priority=3
```

- [ ] **Step 4: Завести follow-up bd issue про реструктуризацию `progress.failed`**

Сейчас `failed: [(title: String, error: String)]` не содержит libid. Если потребуется фича «повторить выгрузку только упавших», нужен рефакторинг типа на `[(libid: Int32, title: String, error: String)]`:

```
bd create --title="ExportProgress.failed: добавить libid в кортеж" --description="Сейчас failed хранит только (title, error). Для будущей фичи 'повторить только упавшие' нужен libid. Изменить тип на [(libid: Int32, title: String, error: String)], обновить ExportRunner.run и UI-консьюмеров." --type=task --priority=4
```

- [ ] **Step 5: Закрыть beads issue fb-loader-ewm**

```
bd close fb-loader-ewm
```

- [ ] **Step 6: Дождаться явного разрешения Alexey на push, потом `git push -u origin fix/clear-checkmark-after-export-fb-loader-ewm`.**

---

## Self-Review

### Покрытие спеки (issue fb-loader-ewm)

- **«После успешной выгрузки книги её галочка должна автоматически сниматься»** — Task 3 (запись в `succeeded`) + Task 5/6 (`.onChange` + финальный пересчёт после `await run`). Снятие происходит по факту каждой книги. Финальный пересчёт после `await run` закрывает race с in-flight книгой при отмене/закрытии.
- **«Чтобы повторно не уезжала при следующей выгрузке»** — Task 1 (тест `keepsFailedChecked`), Task 3 (`succeeded` заполняется только в else-ветке).
- **«Пользователь видел, что именно уже скачано»** — покрыто частично: в текущей сессии галочка исчезает в момент выгрузки. Книги, скачанные в прошлых сессиях, не отличаются от не-скачанных — follow-up issue в Task 10 Step 3.

### Архитектурные инварианты

- **Порядок операций в `ExportRunner.run`:** запись в `succeeded`/`failed` ДО `done += 1`. Иначе `.onChange(of: progress.done)` в родительской вьюхе прочитает `succeeded`, в которое ещё не записан libid этой итерации, — получится визуальный лаг на одну книгу. Зафиксировано комментарием в коде.
- **Финальный пересчёт после `await run`** — нужен. `.onChange` не сработает при переходе `state.exportProgress?.done` на `nil` (optional-chain даст `nil`, тело no-op). Сценарий: пользователь нажал «Отмена», затем сразу «Закрыть» — `state.exportProgress = nil` выставился, sheet закрылся; в этот момент в run-loop'е ещё крутится последняя итерация (await на detached). Когда detached вернётся, run запишет libid в `progress.succeeded` (объект жив через capture в `Task`), но `.onChange` на `state.exportProgress?.done` уже не сработает — биндинг nil. Финальный пересчёт после `await run` берёт уже-полное `succeeded` и закрывает этот пробел.
- **Concurrency.** `ExportProgress` — `@MainActor @Observable`. Запись в `succeeded` идёт только из `ExportRunner.run` (`@MainActor`). Чтение в `.onChange` и в `runExport`-Task — тоже MainActor. Гонок нет. Тяжёлый I/O в `Task.detached` не трогает `progress.succeeded` — только возвращает errorMessage.
- **Идемпотентность.** `Set.subtracting` на пустом или повторном `succeeded` — no-op. Многократный вызов `.onChange` (при каждом инкременте `done`) безопасен.

### Edge cases

- **Дубль libid в items.** `ExportPlanner.plan` принимает `Set<Int32>` — дубликаты на входе невозможны. `Set.insert` всё равно схлопнул бы. `failed.append` — массив, дубликат дал бы две записи, но при `Set<Int32>` на входе ExportPlanner это исключено.
- **Orphan libid в `checkedBookLibids`.** Если каталог перезагружен между check'ом и export'ом, `checkedBookLibids` могут содержать libid'ы, которых нет в `library.bookByLibid`. `ExportPlanner.plan` фильтрует через `compactMap`; orphan libid'ы остаются в `checkedBookLibids` — приемлемо (не выгружались → не снимаем).
- **Failed покрывает не только zip read errors.** `catch` в `ExportRunner.run` ловит любую ошибку: zip read, `FileManager` write (диск переполнен, нет прав). `succeeded` в этих случаях не растёт.

### Что НЕ покрыто тестами и почему

- **Запись `libid` в `succeeded` при успешной выгрузке** (`progress.succeeded.insert(book.libid)` в else-ветке `ExportRunner.run`). Юнит-тест требует zip-архива с FB2 внутри; в проекте нет zip-writer'а и нет тестовых zip-фикстур. Создавать инфраструктуру для одной строчки — overengineering. Покрывается код-ревью + ручным сценарием 1 Task 7.
- **Сброс `progress.succeeded = []` в init-блоке `run`.** Юнит-тест с `items: []` зелёный при любом расположении этой строки и потому бессмысленен. Реальный тест требует zip-инфраструктуры (см. выше). Защита от reuse — обоснована симметрией с `progress.failed = []`, покрывается код-ревью.
- **Поведение `.onChange` и финальный пересчёт в вьюхах.** SwiftUI binding-уровень. Бизнес-логика выделена в `ExportProgress.subtractingSucceeded(from:)` — покрыта юнит-тестами Task 1. View-уровень — ручные сценарии Task 7.
- **Cancel mid-flight юнит-тестом.** Недетерминируемо в текущей архитектуре (microsecond-scale fb2 успевает прогнаться раньше, чем тест выставит cancelled). Покрывается ручным сценарием 3 Task 7.

### Type/consistency

- `succeeded: Set<Int32>` — совпадает с `Book.libid: Int32`, с `AppState.checkedBookLibids: Set<Int32>`, с `SearchCoordinator.checkedBookLibids: Set<Int32>`.
- `subtractingSucceeded(from: Set<Int32>) -> Set<Int32>` — единая сигнатура для обоих окон.
- `progress.succeeded = []` в init-блоке `run` — симметрично с `progress.failed = []`.
