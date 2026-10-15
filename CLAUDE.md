# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## Development Process

Объём процесса зависит от задачи. Перед началом называю класс вслух («это небольшая правка — дизайн в чате»); Alexey может поднять класс. При сомнении беру более тяжёлый класс; если по ходу всплыла сложность — останавливаюсь и поднимаю класс.

**Небольшая правка** — меняет уже существующий flow, затрагивает несколько файлов, не вводит новых контрактов между компонентами (пример: условие активности кнопки, мелкий фикс):
1. Короткий дизайн в чате: что меняю, какие файлы, какие тесты. Ждать «да» Alexey.
2. Ветка от main → тесты → реализация → прогон тестов.
3. Если правка меняет поведение, описанное в существующей спеке, — поправить там соответствующую фразу.
4. UI — ручная проверка Alexey, затем коммит; backend — коммит после зелёных тестов.
5. Одно ревью кода (`superpowers:requesting-code-review`: соответствие дизайну + качество) → фикс → тесты.

**Архитектурная задача** — новая подсистема, новый или изменённый контракт/инвариант между компонентами:
1. Спека `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` → ревьюер-субагент → утверждение Alexey.
2. План `docs/superpowers/plans/YYYY-MM-DD-<topic>.md` через `superpowers:writing-plans` (он сам сверяет план со спекой) → утверждение Alexey.
3. Ветка от main → TDD → реализация.
4. UI — ручная проверка Alexey, затем коммит; backend — коммит после зелёных тестов.
5. Одно ревью кода по спеке и плану (соответствие + качество) → фикс → тесты. Если финальное ревью ветки уже прошло внутри `executing-plans`/`subagent-driven-development`, отдельно не повторять.

### Правила для обоих классов

- Работа только в feature-ветке, не в main. Тесты пишутся до реализации.
- Если Alexey говорит, что что-то не работает, — сначала проверить по фактам, потом отвечать.
- Findings из любого ревью: к Alexey — только архитектура (где живёт компонент, контракт API, инвариант) и бизнес-поведение (что должно произойти, UX, что считается корректным). Остальное (формулировки, опечатки, ссылки на код, тестовая обвязка, локальные паттерны SwiftUI, follow-up'ы без бизнес-смысла) чиню сам до зелёного ревью. Если сомневаюсь — эскалирую.
- Мерж и пуш — только по явной команде Alexey («мержи», «мерж», «да»), на каждое действие отдельно; мерж ≠ пуш. При двусмысленности — переспросить.

## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference
- Use `bd remember` for project knowledge — NOT memory files
- Personal feedback (how to work with Alexey) stays in memory files

## Session Completion

**When ending a work session**, complete these steps:

1. **File issues for remaining work** — create beads for anything that needs follow-up.
2. **Run quality gates** (if code changed) — tests, linters, builds.
3. **Update issue status** — close finished work, update in-progress items.
4. **`bd dolt push`** — push beads data to remote.
5. **Hand off** — provide context for next session.
6. **Мерж/пуш в git** — ТОЛЬКО по явной команде Alexey (см. «Порядок разработки»). Незакоммиченную работу — оставить, и явно сообщить Alexey: «X закоммичено локально, не запушено, ждёт твоего ОК».

> Никаких «MANDATORY PUSH» — push в `origin` без явного разрешения Alexey запрещён.

## Build & Test

```bash
# macOS test suite (Swift Testing framework)
xcodebuild -project "FB Loader/FB Loader.xcodeproj" \
           -scheme "FB Loader" \
           -destination "platform=macOS" \
           test
```

## Architecture Overview

macOS Swift 6 / SwiftUI приложение, открывает INPX-индекс библиотеки Flibusta + папку zip-архивов, показывает каталог с группировкой по авторам/сериям/жанрам и выгружает выбранные FB2 файлы. Архитектура: `INPX → бинарный кэш Library → in-memory snapshot`. Все запросы (фильтр сайдбара, кросс-сущностный fuzzy-поиск, экспорт) — in-memory поверх готовой `Library`.

Подробности — в spec-файлах в `docs/superpowers/specs/`.

## Conventions & Patterns

- **Поиск по символам — через LSP, не через grep.** В проекте установлен `swift-lsp` plugin (SourceKit-LSP). Для всего, что есть символ — свойство, метод, тип, enum-case, протокол — использовать LSP-операции (`findReferences`, `goToDefinition`, `hover`, `workspaceSymbol`, `documentSymbol`). grep оставлен только для текстовых паттернов (TODO-комментарии, строковые литералы, поиск по regex). Семантические запросы grep'ом дают ложные срабатывания (комментарии, одноимённые локальные, строки) и пропуски (квалифицированные ссылки).
- **Swift 6 strict concurrency.** Проект собирается с `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — все типы/функции по умолчанию MainActor-isolated. Для CPU-bound кода (парсеры, скоры, индексы), который вызывается из background-задач (`Task.detached`, `DispatchQueue.concurrentPerform`), помечать **`nonisolated`** на типе или функции. Где нужно — `Sendable` conformance.
- **`Library` — `nonisolated final class … : Sendable`,** все stored properties — `let`-ы, mutate'ить нельзя после `init`. Любой новый параллельный массив (lowercased-кеш, search-key) добавляется по тому же паттерну.
- **Тесты — Swift Testing**, не XCTest. `import Testing`, `@Suite`, `@Test`, `#expect`. Файлы — в `FB Loader/FB LoaderTests/`.
- **Xcode `PBXFileSystemSynchronizedRootGroup`** — новые `.swift`-файлы внутри отслеживаемых директорий автоматически попадают в build target, никаких ручных правок `project.pbxproj` не требуется.
