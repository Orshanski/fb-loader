# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## Development Process — IMPERATIVE

**Правило: после любого артефакта — ревью.** Артефакт = спека, план, код. Ничего не «закоммитили и поехали»: каждый артефакт проходит через ревьюера + утверждение Alexey.

### Порядок разработки (ОБЯЗАТЕЛЬНЫЙ)

1. **Спека.** `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`.
2. **Ревью спеки.** Запустить ревьюера (`superpowers:code-reviewer`-субагент или эквивалент), показать Alexey ВСЕ findings без фильтрации.
3. **Фикс спеки.** Исправить по findings + утверждение Alexey.
4. **План.** `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`, TDD-разбивка через `superpowers:writing-plans`.
5. **Ревью плана.** Запустить ревьюера, показать Alexey ВСЕ findings.
6. **Фикс плана.** Исправить + утверждение Alexey.
7. **Ветка.** Создать feature branch от main. **Никогда не работать в main.**
8. **Тесты.** Написать тесты ПЕРЕД реализацией (TDD).
9. **Реализация.** Код, прогон тестов.
10. **Ручное тестирование Alexey — *когда возможно*.** Чисто-backend таски (парсер, скорер, индекс, in-memory логика — всё, что не даёт визуальной поверхности) проходят автоматически: зелёный test-suite + ревьюер достаточны. **UI-таски** (окна, view, кнопки, формы) — **обязательно** ждут ручной проверки Alexey перед коммитом.
11. **Коммит.** Только после одобрения Alexey для UI-тасков; для backend — после прохождения тестов.
12. **Спек-ревью кода.** Запустить ревьюера на соответствие кода спеке, показать ВСЕ findings.
13. **Код-ревью.** Запустить ревьюера на качество кода, показать ВСЕ findings.
14. **Фикс findings.** Исправить все замечания, повторить тесты.
15. **Мерж.** ТОЛЬКО по явной команде Alexey («мержи», «мерж», «да»).
16. **Пуш.** ТОЛЬКО по явной команде Alexey. Мерж ≠ пуш — разрешение на каждое действие отдельно.

### Правила

- **НЕ СПОРИТЬ с Alexey.** Если Alexey говорит, что что-то не работает или сломано — СНАЧАЛА проверить, потом отвечать. Не доверять своим предположениям, доверять фактам.
- **Эскалация findings из ревью — только архитектура и бизнес-поведение.**
  - **К Alexey:** изменения семантики продукта (что должно произойти, какой UX), архитектурные развилки (где жить компоненту, какой контракт у API, какой инвариант), бизнес-правила (что считается корректным результатом).
  - **Чиню сам до зелени:** формулировки, нечёткие фразы, стилистика, опечатки, повторы, ссылки на код, мелкие неточности в счётчиках, тестовая обвязка (`@MainActor` на suite, имена кейсов, разбивка), технические нюансы реализации (атомарность API, локальные паттерны SwiftUI), follow-up'ы без бизнес-смысла.
  - Если сомневаюсь — отношу к архитектуре/бизнесу и эскалирую, не наоборот.
- **НИКОГДА не мержить/пушить без явного разрешения.** При любой двусмысленности — переспросить.
- **Never work in main.** Always create a feature branch.
- **TDD:** tests first, then implementation.

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
