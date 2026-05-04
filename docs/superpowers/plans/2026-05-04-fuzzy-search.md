# Fuzzy Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Реализовать fuzzy-поиск по библиотеке (`docs/superpowers/specs/2026-05-04-fuzzy-search-design.md`): отдельное окно «Поиск по библиотеке» с тремя группами результатов (Авторы / Серии / Совпадения по книгам), bit-parallel fuzzy-скорер на чистом Swift с порогом 75, синхронной сборкой индекса в `Library.init` и собственным экспортом из окна.

**Architecture:** Все вычисления in-memory поверх существующего `Library`-снапшота. Скорер — порт `token_min_ratio` из `librarium-py` через bit-parallel LCS (Hyyrö'04, адаптация из `rapidfuzz-cpp/distance/LCSseq_impl.hpp`, MIT). Pre-built `LcsPattern` для query-токенов + cutoff pruning дают ~420 мс на 581k книг при триггере по кнопке. Search-ключи строятся транзиентно в `Library.init`, не персистятся в бинарный кэш.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Observation. Без сторонних зависимостей.

**Reference:** Эталонный спайк-код, валидированный на реальном кэше (581k книг / 167k авторов / 69k серий) — `~/code/fb-loader-search-spike/spike3.swift`. Все алгоритмические части (preprocess, LCS DP, LCS BP, pre-built PMV, scorer, parallel scan) проверены и должны переноситься оттуда дословно.

**Корпус-эталон** (13 пар, прошёл в спайке) — переезжает в `FuzzyScorerTests.swift`. Любая регрессия в этом корпусе блокирует коммит.

---

## File Map

### Создаются

- `FB Loader/FB Loader/Search/SearchPreprocess.swift` — `preprocessTokens(_:)` нормализует строку и разбивает на массив `[UInt32]`-токенов (lowercase, ё→е, не-letter/digit как разделитель).
- `FB Loader/FB Loader/Search/FuzzyScorer.swift` — `lcsLengthDP`, `lcsLengthBP`, `LcsPattern`, `makeLcsPattern`, `lcsLengthPre`, `tokenMatchScorePre`, `tokenMinRatioPre`, `SCORE_CUTOFF`.
- `FB Loader/FB Loader/Search/SearchResult.swift` — value types: `AuthorMatch`, `SeriesMatch`, `BookMatch`, `SearchResults`.
- `FB Loader/FB Loader/Search/SearchEngine.swift` — `nonisolated enum SearchEngine` с `func run(query:language:in:) -> SearchResults`, параллельный скан по авторам/сериям/книгам.
- `FB Loader/FB Loader/Search/SearchCoordinator.swift` — `@Observable final class SearchCoordinator`, владеет состоянием окна поиска (query, language, selection, checks, results, paging).
- `FB Loader/FB Loader/UI/Search/SearchWindowView.swift` — корневой View сцены, верхний бар + список + деталь.
- `FB Loader/FB Loader/UI/Search/SearchResultListView.swift` — sectioned scroll, маршрутизирует группы.
- `FB Loader/FB Loader/UI/Search/SearchAuthorBlock.swift` — заголовок «автор &lt;имя&gt;» + книги автора (одиночные + по сериям) с collapse.
- `FB Loader/FB Loader/UI/Search/SearchSeriesBlock.swift` — заголовок «серия &lt;имя&gt;» + книги серии по `seriesNum` с collapse.
- `FB Loader/FB Loader/UI/Search/SearchBooksBucketView.swift` — бакет «Совпадения по книгам» с пагинацией +20.
- `FB Loader/FB LoaderTests/SearchPreprocessTests.swift`
- `FB Loader/FB LoaderTests/FuzzyScorerTests.swift`
- `FB Loader/FB LoaderTests/SearchEngineTests.swift`

### Модифицируются

- `FB Loader/FB Loader/Models/Library.swift` — добавить транзиентные `searchKeyAuthors`/`searchKeySeries`/`searchKeyTitle` + `searchAuthorIdx`/`searchSeriesIdx`, заполнить в `init`. Добавить `onStatus("Считаем индексы поиска…")` между фазами.
- `FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift` — выделить `BookRow` из приватной структуры в самостоятельный файл с инжектируемыми bindings; рефакторнуть `LanguageFilterPicker` на `Binding<String>` параметр.
- `FB Loader/FB Loader/UI/BooksTable/BookRow.swift` (новый) — переехавший компонент.
- `FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift` — добавить кнопку-лупу рядом с пикером вкладок, открывающую сцену поиска.
- `FB Loader/FB Loader/FB_LoaderApp.swift` — добавить вторую сцену `Window("Поиск по библиотеке", id: "library-search")`.

---

## Task 1: SearchPreprocess

**Files:**
- Create: `FB Loader/FB Loader/Search/SearchPreprocess.swift`
- Test: `FB Loader/FB LoaderTests/SearchPreprocessTests.swift`

- [ ] **Step 1: Write failing tests**

Create `FB Loader/FB LoaderTests/SearchPreprocessTests.swift`:

```swift
import Testing
import Foundation
@testable import FB_Loader

@Suite("SearchPreprocess")
struct SearchPreprocessTests {
    @Test("Пустая строка → пустой массив токенов")
    func empty() {
        #expect(preprocessTokens("") == [])
    }

    @Test("Простое слово ASCII → один токен в нижнем регистре")
    func asciiWord() {
        let toks = preprocessTokens("Hello")
        #expect(toks.count == 1)
        #expect(String(String.UnicodeScalarView(toks[0].compactMap(Unicode.Scalar.init))) == "hello")
    }

    @Test("Кириллица в нижнем регистре")
    func cyrillicLowercase() {
        let toks = preprocessTokens("Сандерсон")
        #expect(toks.count == 1)
        #expect(String(String.UnicodeScalarView(toks[0].compactMap(Unicode.Scalar.init))) == "сандерсон")
    }

    @Test("ё → е, Ё → е")
    func yoToYe() {
        let lower = preprocessTokens("ёлка")
        let upper = preprocessTokens("Ёлка")
        #expect(String(String.UnicodeScalarView(lower[0].compactMap(Unicode.Scalar.init))) == "елка")
        #expect(String(String.UnicodeScalarView(upper[0].compactMap(Unicode.Scalar.init))) == "елка")
    }

    @Test("Пунктуация и пробелы — разделители токенов, схлопываются")
    func punctuationSplits() {
        let toks = preprocessTokens("Война и мир!  ")
        #expect(toks.count == 3)
        let words = toks.map { String(String.UnicodeScalarView($0.compactMap(Unicode.Scalar.init))) }
        #expect(words == ["война", "и", "мир"])
    }

    @Test("Цифры сохраняются")
    func digitsKept() {
        let toks = preprocessTokens("1984")
        #expect(toks.count == 1)
        #expect(String(String.UnicodeScalarView(toks[0].compactMap(Unicode.Scalar.init))) == "1984")
    }

    @Test("Микс ASCII и кириллицы в одном слове")
    func mixedScript() {
        let toks = preprocessTokens("ABC123фыв")
        #expect(toks.count == 1)
        #expect(String(String.UnicodeScalarView(toks[0].compactMap(Unicode.Scalar.init))) == "abc123фыв")
    }

    @Test("Тире и табы — разделители")
    func dashTabAreSeparators() {
        let toks = preprocessTokens("foo-bar\tbaz")
        let words = toks.map { String(String.UnicodeScalarView($0.compactMap(Unicode.Scalar.init))) }
        #expect(words == ["foo", "bar", "baz"])
    }

    @Test("Украинская кириллица (і, ї, є, ґ) считается буквой")
    func ukrainianCyrillic() {
        let toks = preprocessTokens("Україна")
        #expect(toks.count == 1, "слово 'Україна' должно остаться одним токеном, не порезаться на 'кра' + 'на'")
    }

    @Test("Латиница с диакритикой считается буквой")
    func latinDiacritics() {
        let toks = preprocessTokens("naïve")
        #expect(toks.count == 1)
    }
}
```

- [ ] **Step 2: Run tests (expect failure — `preprocessTokens` не существует)**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/SearchPreprocess" 2>&1 | tail -30`
Expected: FAIL with "cannot find 'preprocessTokens' in scope".

- [ ] **Step 3: Implement preprocessTokens**

Create `FB Loader/FB Loader/Search/SearchPreprocess.swift`:

```swift
import Foundation

/// Normalises a string and splits it into a sequence of `[UInt32]` codepoint
/// tokens for fuzzy-matching consumption by `FuzzyScorer`.
///
/// Steps (applied in order):
/// 1. ё/Ё → е/Е (rapidfuzz default_process не делает этого; librarium делает,
///    потому что русские читатели часто пишут «е» вместо «ё»).
/// 2. Lowercase для ASCII A..Z и кириллицы А..Я (по диапазонам, без
///    `String.lowercased()` — избегаем grapheme-cluster overhead в горячем
///    цикле).
/// 3. Любой не-буквенный/не-цифровой codepoint — разделитель токенов.
///    Буквенность проверяем через `Unicode.Scalar.properties.isAlphabetic` —
///    это покрывает украинскую кириллицу (і, ї, є, ґ), белорусскую (ў),
///    латиницу с диакритикой (é, ü, ł) и пр. Без этого port-плана срезал бы
///    легитимные буквы во многих именах (см. ревью C2).
///
/// Возвращает массив непустых токенов, каждый — массив raw scalar.value
/// (UInt32). Скорер дальше работает на UInt32 и не возвращается в `String`.
///
/// `nonisolated` обязательно: проект собирается с
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, и без этой пометки функция
/// окажется MainActor-isolated, что сломает её вызов из `Task.detached`
/// внутри `SearchCoordinator` и из `DispatchQueue.concurrentPerform`.
@inline(__always)
nonisolated func isAlnumScalar(_ s: UInt32) -> Bool {
    if s >= 0x30 && s <= 0x39 { return true }       // ASCII digits 0..9
    guard let scalar = Unicode.Scalar(s) else { return false }
    return scalar.properties.isAlphabetic
}

nonisolated func preprocessTokens(_ raw: String) -> [[UInt32]] {
    if raw.isEmpty { return [] }
    var tokens: [[UInt32]] = []
    var current: [UInt32] = []
    current.reserveCapacity(16)
    for u in raw.unicodeScalars {
        var c = u.value
        // ё/Ё → е/Е
        if c == 0x0451 { c = 0x0435 }
        else if c == 0x0401 { c = 0x0435 }
        // ASCII upper → lower
        if c >= 0x41 && c <= 0x5A { c += 0x20 }
        // Cyrillic upper А..Я → а..я
        else if c >= 0x0410 && c <= 0x042F { c += 0x20 }
        if isAlnumScalar(c) {
            current.append(c)
        } else if !current.isEmpty {
            tokens.append(current)
            current = []
            current.reserveCapacity(16)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/SearchPreprocess" 2>&1 | tail -30`
Expected: 8/8 passes.

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/Search/SearchPreprocess.swift" "FB Loader/FB LoaderTests/SearchPreprocessTests.swift"
git commit -m "feat(search): add SearchPreprocess (lowercase + ё→е + tokenisation)"
```

---

## Task 2: FuzzyScorer (DP variant + corpus)

**Files:**
- Create: `FB Loader/FB Loader/Search/FuzzyScorer.swift`
- Test: `FB Loader/FB LoaderTests/FuzzyScorerTests.swift`

- [ ] **Step 1: Write failing corpus tests**

Create `FB Loader/FB LoaderTests/FuzzyScorerTests.swift`:

```swift
import Testing
import Foundation
@testable import FB_Loader

@Suite("FuzzyScorer corpus")
struct FuzzyScorerCorpusTests {
    /// Эталонные пары из `librarium-py/backend/app/search.py`
    /// (комментарий к `_token_match_score`) + edge-кейсы по нормализации.
    /// Любая регрессия здесь — баг.
    private static let corpus: [(q: String, c: String, pass: Bool, label: String)] = [
        ("прошивка", "прошивки", true, "склонение"),
        ("достоевск", "достоевский", true, "префикс"),
        ("короли", "королей", true, "склонение-окончания"),
        ("сандерсн", "сандерсон", true, "опечатка-1"),
        ("короли", "космобиолухи", false, "ложный LCS"),
        ("крыса", "корсакова", false, "ложный LCS"),
        ("мария", "информация", false, "шумная подстрока"),
        ("мария", "марк", false, "короткое vs короткое"),
        ("ёлка", "елка", true, "ё/е"),
        ("Тайфун!", "тайфуны", true, "пунктуация"),
        ("  достоевск  ", "Достоевский", true, "регистр+пробелы"),
        ("сандерсон брэндон", "Брэндон Сандерсон", true, "перестановка слов"),
        ("толк", "толкиен", false, "короткий префикс — drop"),
    ]

    @Test("13 эталонных пар librarium корректно ранжируются")
    func corpusFullPass() {
        for tc in Self.corpus {
            let qTokens = preprocessTokens(tc.q)
            let cTokens = preprocessTokens(tc.c)
            let score = tokenMinRatio(qTokens: qTokens, cTokens: cTokens)
            let actualPass = score >= SCORE_CUTOFF
            #expect(actualPass == tc.pass,
                    "\(tc.label): \(tc.q) → \(tc.c) — score \(score), expected \(tc.pass ? "≥75" : "<75")")
        }
    }

    @Test("Пустые входы дают 0")
    func emptyInputs() {
        #expect(tokenMinRatio(qTokens: [], cTokens: [[0x61]]) == 0)
        #expect(tokenMinRatio(qTokens: [[0x61]], cTokens: []) == 0)
    }

    @Test("SCORE_CUTOFF равен 75")
    func cutoffConstant() {
        #expect(SCORE_CUTOFF == 75.0)
    }
}
```

- [ ] **Step 2: Run tests (expect failure — функции не существуют)**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/FuzzyScorer corpus" 2>&1 | tail -30`
Expected: FAIL.

- [ ] **Step 3: Implement DP-based scorer**

Create `FB Loader/FB Loader/Search/FuzzyScorer.swift`:

```swift
import Foundation

/// SCORE cutoff used to separate real matches from noise.
/// Empirically (librarium): real matches land at 80–100, noise ≤66.
/// 75 sits in the gap. Tune via the corpus tests if behaviour drifts.
///
/// `nonisolated` обязательно — глобальная константа, которой пользуются
/// background-задачи (см. C1 в ревью плана).
nonisolated public let SCORE_CUTOFF: Double = 75.0

/// Standard 1D rolling DP — used as the reference and as the fallback for
/// patterns longer than 64 codepoints (where bit-parallel won't fit in a
/// single UInt64 register).
nonisolated func lcsLengthDP(_ a: [UInt32], _ b: [UInt32]) -> Int {
    let m = a.count, n = b.count
    if m == 0 || n == 0 { return 0 }
    let (s, t): ([UInt32], [UInt32]) = m < n ? (b, a) : (a, b)
    let cols = t.count + 1
    var prev = [Int](repeating: 0, count: cols)
    var cur  = [Int](repeating: 0, count: cols)
    for i in 1...s.count {
        let si = s[i - 1]
        for j in 1...t.count {
            if si == t[j - 1] {
                cur[j] = prev[j - 1] + 1
            } else {
                cur[j] = max(prev[j], cur[j - 1])
            }
        }
        swap(&prev, &cur)
    }
    return prev[t.count]
}

/// Naïve scorer (used by the non-pre-built `tokenMinRatio` for the DP corpus
/// path). Bit-parallel + pre-built variants for production are added in Task 3.
@inline(__always)
nonisolated func tokenMatchScore(_ q: [UInt32], _ c: [UInt32]) -> Double {
    if q.isEmpty || c.isEmpty { return 0 }
    let lcs = lcsLengthDP(q, c)
    let lcsCov = Double(lcs) / Double(q.count) * 100.0
    let ratio = Double(lcs) * 200.0 / Double(q.count + c.count)
    return min(lcsCov, ratio)
}

/// `token_min_ratio` semantics: every query-token must find a best match in
/// some choice-token; the weakest per-token best across the query drags the
/// final min(...) score down.
nonisolated func tokenMinRatio(qTokens: [[UInt32]], cTokens: [[UInt32]]) -> Double {
    if qTokens.isEmpty || cTokens.isEmpty { return 0 }
    var minScore = Double.infinity
    for qt in qTokens {
        var bestForQ = 0.0
        for ct in cTokens {
            let s = tokenMatchScore(qt, ct)
            if s > bestForQ { bestForQ = s }
            if bestForQ >= 100.0 { break }
        }
        if bestForQ < minScore { minScore = bestForQ }
        if minScore == 0 { return 0 }
    }
    return minScore == .infinity ? 0 : minScore
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/FuzzyScorer corpus" 2>&1 | tail -30`
Expected: 3/3 passes (corpus + emptyInputs + cutoffConstant).

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/Search/FuzzyScorer.swift" "FB Loader/FB LoaderTests/FuzzyScorerTests.swift"
git commit -m "feat(search): add FuzzyScorer DP + librarium corpus tests"
```

---

## Task 3: FuzzyScorer (bit-parallel + pre-built PMV)

**Files:**
- Modify: `FB Loader/FB Loader/Search/FuzzyScorer.swift`
- Modify: `FB Loader/FB LoaderTests/FuzzyScorerTests.swift`

- [ ] **Step 1: Add failing cross-check + pre-built tests**

Append in `FuzzyScorerTests.swift` (inside the file, after `FuzzyScorerCorpusTests`):

```swift
@Suite("FuzzyScorer bit-parallel")
struct FuzzyScorerBPTests {
    /// Genering все пары из корпуса + дополнительные ровно для cross-check.
    private static let pairs: [(q: String, c: String)] = [
        ("прошивка", "прошивки"),
        ("достоевск", "достоевский"),
        ("короли", "королей"),
        ("сандерсн", "сандерсон"),
        ("короли", "космобиолухи"),
        ("крыса", "корсакова"),
        ("мария", "информация"),
        ("мария", "марк"),
        ("ёлка", "елка"),
        ("Тайфун!", "тайфуны"),
        ("сандерсон брэндон", "Брэндон Сандерсон"),
        ("толк", "толкиен"),
        ("a", "abcdefghijklmnopqrstuvwxyz"),
        ("abcdefghijklmnopqrstuvwxyz", "a"),
        ("", ""),
    ]

    @Test("DP ≡ BP на всех парах токенов корпуса")
    func dpEqualsBP() {
        for (q, c) in Self.pairs {
            let qToks = preprocessTokens(q)
            let cToks = preprocessTokens(c)
            for qt in qToks {
                for ct in cToks {
                    let dp = lcsLengthDP(qt, ct)
                    let bp = lcsLengthBP(qt, ct)
                    #expect(dp == bp, "\(q) × \(c): DP=\(dp), BP=\(bp)")
                }
            }
        }
    }

    @Test("Pre-built scorer даёт те же скоры, что и не-pre-built вариант")
    func preBuiltMatchesNaive() {
        for tc in FuzzyScorerCorpusTests.corpus {
            let qToks = preprocessTokens(tc.q)
            let cToks = preprocessTokens(tc.c)
            let naive = tokenMinRatio(qTokens: qToks, cTokens: cToks)
            let qPatterns = qToks.map(makeLcsPattern)
            let pre = tokenMinRatioPre(qPatterns: qPatterns, cTokens: cToks,
                                       cutoff: SCORE_CUTOFF)
            // Pre с cutoff может вернуть 0 раньше naive — но именно когда
            // `naive < cutoff`. В остальных случаях должны совпадать.
            if naive >= SCORE_CUTOFF {
                #expect(abs(pre - naive) < 0.01,
                        "\(tc.label): \(tc.q) → \(tc.c) — naive=\(naive), pre=\(pre)")
            } else {
                #expect(pre == 0,
                        "\(tc.label): \(tc.q) → \(tc.c) — pre=\(pre), expected 0 due to cutoff")
            }
        }
    }

    @Test("Паттерн >64 codepoint'ов уходит в DP-fallback и работает корректно")
    func longPatternFallback() {
        let longPat = String(repeating: "а", count: 70)
        let target = "а"
        let qToks = preprocessTokens(longPat)
        let cToks = preprocessTokens(target)
        let qPatterns = qToks.map(makeLcsPattern)
        #expect(qPatterns[0].isLong == true)
        // LCS должен быть 1: "а" есть один раз в обеих строках, и "а"
        // покрывается из паттерна длины 70.
        #expect(lcsLengthPre(qPatterns[0], cToks[0]) == 1)
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL (`lcsLengthBP`/`makeLcsPattern`/`tokenMinRatioPre` не существуют)**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/FuzzyScorer bit-parallel" 2>&1 | tail -30`
Expected: FAIL with "cannot find ... in scope".

- [ ] **Step 3: Add bit-parallel + pre-built implementations**

Append at the end of `FB Loader/FB Loader/Search/FuzzyScorer.swift`:

```swift
// MARK: - Bit-parallel LCS (Hyyrö 2004)
//
// Adapted from `rapidfuzz-cpp/rapidfuzz/distance/LCSseq_impl.hpp` (MIT,
// © Max Bachmann). For patterns ≤64 codepoints — O(n) with a 4-op inner
// loop on a single UInt64 register. Falls back to DP for longer patterns
// (rare in our use case — words rarely exceed 30 chars).

@inline(__always)
nonisolated func lcsLengthBP(_ a: [UInt32], _ b: [UInt32]) -> Int {
    let m = a.count, n = b.count
    if m == 0 || n == 0 { return 0 }
    // Pattern is the shorter of the two so it fits in a single UInt64.
    let (pat, txt): ([UInt32], [UInt32]) = m <= n ? (a, b) : (b, a)
    if pat.count > 64 { return lcsLengthDP(a, b) }
    var pmv = [UInt32: UInt64](minimumCapacity: pat.count)
    for (i, c) in pat.enumerated() {
        pmv[c, default: 0] |= UInt64(1) << i
    }
    var S = UInt64.max
    for c in txt {
        guard let matches = pmv[c] else { continue }
        let u = S & matches
        S = (S &+ u) | (S &- u)
    }
    return (~S).nonzeroBitCount
}

// MARK: - Pre-built query pattern
//
// Bit-parallel сам по себе не даёт ускорения, потому что Swift Dictionary
// аллоцируется на каждом вызове lcsLength (миллионы раз). Ключевая опт:
// PMV для каждого query-токена строится ОДИН раз на нажатие «Поиск» и
// переиспользуется на всех 581k+ кандидатах. На спайке это даёт ~6×.

/// `nonisolated ... : Sendable` так как объект разделяется между потоками
/// в `parallelScan` (`DispatchQueue.concurrentPerform`) и пересекается через
/// `Task.detached` boundary в `SearchCoordinator`. Все поля let-овые и
/// иммутабельные после init — Sendable conformance безопасен (см. C1).
nonisolated struct LcsPattern: Sendable {
    let m: Int
    let pmv: [UInt32: UInt64]   // empty if isLong
    let isLong: Bool
    let fallback: [UInt32]      // raw scalars for DP fallback if isLong
}

nonisolated func makeLcsPattern(_ pat: [UInt32]) -> LcsPattern {
    if pat.count > 64 {
        return LcsPattern(m: pat.count, pmv: [:], isLong: true, fallback: pat)
    }
    var pmv = [UInt32: UInt64](minimumCapacity: pat.count)
    for (i, c) in pat.enumerated() {
        pmv[c, default: 0] |= UInt64(1) << i
    }
    return LcsPattern(m: pat.count, pmv: pmv, isLong: false, fallback: pat)
}

@inline(__always)
nonisolated func lcsLengthPre(_ p: LcsPattern, _ text: [UInt32]) -> Int {
    if p.m == 0 || text.isEmpty { return 0 }
    if p.isLong { return lcsLengthDP(p.fallback, text) }
    var S = UInt64.max
    for c in text {
        guard let matches = p.pmv[c] else { continue }
        let u = S & matches
        S = (S &+ u) | (S &- u)
    }
    return (~S).nonzeroBitCount
}

@inline(__always)
nonisolated func tokenMatchScorePre(_ p: LcsPattern, _ c: [UInt32]) -> Double {
    if p.m == 0 || c.isEmpty { return 0 }
    let lcs = lcsLengthPre(p, c)
    let lcsCov = Double(lcs) / Double(p.m) * 100.0
    let ratio = Double(lcs) * 200.0 / Double(p.m + c.count)
    return min(lcsCov, ratio)
}

/// Production-pace вариант: query-токены передаются как `[LcsPattern]`,
/// уже с pre-built PMV. Дополнительно — cutoff pruning: если для какого-то
/// query-токена лучший скор ниже cutoff, итоговый min(...) тоже будет
/// ниже cutoff, и можно сразу выйти. Сильно режет работу на многословных
/// запросах против большинства кандидатов.
@inline(__always)
nonisolated func tokenMinRatioPre(qPatterns: [LcsPattern], cTokens: [[UInt32]],
                                  cutoff: Double) -> Double {
    if qPatterns.isEmpty || cTokens.isEmpty { return 0 }
    var minScore = Double.infinity
    for qp in qPatterns {
        var bestForQ = 0.0
        for ct in cTokens {
            let s = tokenMatchScorePre(qp, ct)
            if s > bestForQ { bestForQ = s }
            if bestForQ >= 100.0 { break }
        }
        if bestForQ < cutoff { return 0 }     // pruning
        if bestForQ < minScore { minScore = bestForQ }
    }
    return minScore == .infinity ? 0 : minScore
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/FuzzyScorer bit-parallel" 2>&1 | tail -30`
Expected: 3/3 passes.

- [ ] **Step 5: Run ВСЕХ FuzzyScorer-тестов, чтобы корпус не регрессировал**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/FuzzyScorer corpus" -only-testing:"FB LoaderTests/FuzzyScorer bit-parallel" 2>&1 | tail -10`
Expected: All passes.

- [ ] **Step 6: Commit**

```bash
git add "FB Loader/FB Loader/Search/FuzzyScorer.swift" "FB Loader/FB LoaderTests/FuzzyScorerTests.swift"
git commit -m "feat(search): add bit-parallel LCS + pre-built LcsPattern"
```

---

## Task 4: Library search index

**Files:**
- Modify: `FB Loader/FB Loader/Models/Library.swift`
- Modify: `FB Loader/FB LoaderTests/LibraryBinaryCodecTests.swift` (smoke-проверка что init не упал; основные тесты — отдельным файлом, см. Task 6).

- [ ] **Step 1: Add failing test для search-ключей**

Append в `LibraryBinaryCodecTests.swift` (или создай новый `LibrarySearchIndexTests.swift` если хочется чище — но в спайке используем существующий, чтобы не плодить файлы):

```swift
@Test("Library.init строит search-ключи параллельно authors/series/books")
func searchIndicesBuilt() {
    let lib = Library(
        inpxHash: Data(repeating: 0xAB, count: 32),
        inpxVersion: "v",
        archives: ["arch"],
        authors: [
            Author.unknown,
            Author(id: 1, lastName: "Сандерсон", firstName: "Брэндон", middleName: ""),
        ],
        series: [Series(id: 1, name: "Элантрис")],
        genres: [],
        books: [
            Book(libid: 100, title: "Элантрис", authorIDs: [1],
                 seriesID: 1, seriesNum: 1, genreIDs: [],
                 language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
        ]
    )

    #expect(lib.searchKeyAuthors.count == lib.authors.count)
    #expect(lib.searchKeySeries.count == lib.series.count)
    #expect(lib.searchKeyTitle.count == lib.books.count)
    #expect(lib.searchAuthorIdx.count == lib.books.count)
    #expect(lib.searchSeriesIdx.count == lib.books.count)

    // Сандерсон → автор index 1 → токены ["сандерсон", "брэндон"]
    let sandersonTokens = lib.searchKeyAuthors[1]
    #expect(sandersonTokens.count == 2)

    // У книги Элантрис автор Сандерсон (id=1, index=1) и серия Элантрис (id=1, index=0)
    #expect(lib.searchAuthorIdx[0] == 1)
    #expect(lib.searchSeriesIdx[0] == 0)

    // Title key токенизирован
    #expect(lib.searchKeyTitle[0].count == 1)  // одно слово "элантрис"
}

@Test("Книга без серии → searchSeriesIdx == -1")
func searchSeriesIdxNilSentinel() {
    let lib = Library(
        inpxHash: Data(repeating: 0xAB, count: 32),
        inpxVersion: "v",
        archives: ["arch"], authors: [Author.unknown], series: [], genres: [],
        books: [
            Book(libid: 100, title: "Sample", authorIDs: [Author.unknownID],
                 seriesID: nil, seriesNum: nil, genreIDs: [],
                 language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
        ]
    )
    #expect(lib.searchSeriesIdx[0] == -1)
}
```

- [ ] **Step 2: Run, expect FAIL (`searchKeyAuthors` etc. не существуют)**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/LibraryBinaryCodec" 2>&1 | tail -30`

- [ ] **Step 3: Добавить search-ключи в Library**

В `FB Loader/FB Loader/Models/Library.swift`, после существующих `lowercasedSidebarGenreNames`, добавить properties:

```swift
    // MARK: - Search index (transient, built in init, NOT persisted)
    //
    // Token-level fuzzy-search keys, parallel to authors / series / books.
    // Each token is `[UInt32]` — raw codepoints after `preprocessTokens`
    // (lowercase + ё→е + non-alnum-as-separator). Built once at init,
    // ~2 s on full Flibusta-scale catalog (581k books / 167k authors /
    // 69k series). Light variant: per-book keeps only title tokens; for
    // book scoring the engine dispatches author/series tokens via
    // `searchAuthorIdx` / `searchSeriesIdx` lookups.
    let searchKeyAuthors: [[[UInt32]]]  // parallel to authors
    let searchKeySeries:  [[[UInt32]]]  // parallel to series
    let searchKeyTitle:   [[[UInt32]]]  // parallel to books
    let searchAuthorIdx:  [Int32]       // per book: index into searchKeyAuthors, -1 if missing
    let searchSeriesIdx:  [Int32]       // per book: index into searchKeySeries, -1 if no series
```

В `init`, перед закрывающей скобкой (после `print("[Library.init] secondary indices built; ...")` и `onStatus?(...)`), добавить блок:

```swift
        // Search-ключи строятся синхронно — пользователь видит «Считаем
        // индексы поиска…» как часть нормальной загрузки каталога. Стоимость
        // ~2 с на полном каталоге.
        let searchStatus = "Считаем индексы поиска…"
        print("[Library.init] \(searchStatus)")
        onStatus?(searchStatus)

        var sAuthors: [[[UInt32]]] = []
        sAuthors.reserveCapacity(authors.count)
        for a in authors {
            sAuthors.append(preprocessTokens(a.displayName))
        }
        self.searchKeyAuthors = sAuthors

        var sSeries: [[[UInt32]]] = []
        sSeries.reserveCapacity(series.count)
        for s in series {
            sSeries.append(preprocessTokens(s.name))
        }
        self.searchKeySeries = sSeries

        var sTitles: [[[UInt32]]] = []
        sTitles.reserveCapacity(books.count)
        var aIdx: [Int32] = []
        aIdx.reserveCapacity(books.count)
        var sIdx: [Int32] = []
        sIdx.reserveCapacity(books.count)
        // Lookup tables: id → index (мы уже строили *byID Dictionary, но
        // нам нужен индекс в массивах authors/series, не сам объект).
        var authorIndexByID: [Int32: Int] = [:]
        authorIndexByID.reserveCapacity(authors.count)
        for (i, a) in authors.enumerated() { authorIndexByID[a.id] = i }
        var seriesIndexByID: [Int32: Int] = [:]
        seriesIndexByID.reserveCapacity(series.count)
        for (i, s) in series.enumerated() { seriesIndexByID[s.id] = i }
        for b in books {
            sTitles.append(preprocessTokens(b.title))
            // Primary author: first authorID; -1 if missing.
            if let firstAID = b.authorIDs.first,
               let idx = authorIndexByID[firstAID] {
                aIdx.append(Int32(idx))
            } else {
                aIdx.append(-1)
            }
            if let sid = b.seriesID, let idx = seriesIndexByID[sid] {
                sIdx.append(Int32(idx))
            } else {
                sIdx.append(-1)
            }
        }
        self.searchKeyTitle = sTitles
        self.searchAuthorIdx = aIdx
        self.searchSeriesIdx = sIdx
        print("[Library.init] search indices built")
        onStatus?("[Library.init] search indices built")
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/LibraryBinaryCodec" 2>&1 | tail -30`
Expected: existing roundTrip etc. всё ещё проходят (search-ключи транзиентные, не пишутся в кэш) + 2 новых теста зелёные.

- [ ] **Step 5: Verify полный test-suite не сломали**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test 2>&1 | tail -10`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add "FB Loader/FB Loader/Models/Library.swift" "FB Loader/FB LoaderTests/LibraryBinaryCodecTests.swift"
git commit -m "feat(search): build transient search index in Library.init"
```

---

## Task 5: SearchResult value types

**Files:**
- Create: `FB Loader/FB Loader/Search/SearchResult.swift`

- [ ] **Step 1: Создать файл с типами**

Create `FB Loader/FB Loader/Search/SearchResult.swift`:

```swift
import Foundation

/// Один матч-автор: индекс в `Library.authors` + скор.
nonisolated struct AuthorMatch: Sendable {
    let authorIndex: Int
    let score: Double
}

/// Один матч-серия.
nonisolated struct SeriesMatch: Sendable {
    let seriesIndex: Int
    let score: Double
}

/// Один матч-книга.
nonisolated struct BookMatch: Sendable {
    let bookIndex: Int
    let score: Double
}

/// Полный результат одного запроса. Каждый бакет уже отсортирован по
/// убыванию скорера. Для author/series — топ-N matches; для books —
/// все совпадения выше cutoff (UI решает, как пагинировать).
nonisolated struct SearchResults: Sendable {
    let authors: [AuthorMatch]
    let series:  [SeriesMatch]
    let books:   [BookMatch]
}
```

- [ ] **Step 2: Build verify (нет тестов — value types)**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "FB Loader/FB Loader/Search/SearchResult.swift"
git commit -m "feat(search): add SearchResult value types"
```

---

## Task 6: SearchEngine

**Files:**
- Create: `FB Loader/FB Loader/Search/SearchEngine.swift`
- Create: `FB Loader/FB LoaderTests/SearchEngineTests.swift`

- [ ] **Step 1: Написать failing-тесты**

Create `FB Loader/FB LoaderTests/SearchEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import FB_Loader

@Suite("SearchEngine")
struct SearchEngineTests {
    private func makeLibrary() -> Library {
        Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [
                Author.unknown,
                Author(id: 1, lastName: "Сандерсон", firstName: "Брэндон", middleName: ""),
                Author(id: 2, lastName: "Толстой", firstName: "Лев", middleName: "Николаевич"),
                Author(id: 3, lastName: "Стругацкий", firstName: "Аркадий", middleName: ""),
            ],
            series: [
                Series(id: 1, name: "Элантрис"),
                Series(id: 2, name: "Война и мир"),
            ],
            genres: [],
            books: [
                Book(libid: 100, title: "Элантрис", authorIDs: [1],
                     seriesID: 1, seriesNum: 1, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
                Book(libid: 101, title: "Надежда Элантриса", authorIDs: [1],
                     seriesID: 1, seriesNum: 2, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
                Book(libid: 200, title: "Война и мир", authorIDs: [2],
                     seriesID: 2, seriesNum: 1, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
                Book(libid: 300, title: "Понедельник начинается в субботу", authorIDs: [3],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            ]
        )
    }

    @Test("Точный запрос по имени автора находит автора и его книги")
    func authorExactMatch() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "Сандерсон", language: "ru", in: lib)
        #expect(r.authors.contains { lib.authors[$0.authorIndex].lastName == "Сандерсон" })
        // Книги Сандерсона должны быть и в bucket'е книг (через author-токены).
        let bookTitles = r.books.map { lib.books[$0.bookIndex].title }
        #expect(bookTitles.contains("Элантрис"))
        #expect(bookTitles.contains("Надежда Элантриса"))
    }

    @Test("Опечатка в имени автора (1 символ) — всё ещё находит")
    func authorTypo() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "сандерсн", language: "ru", in: lib)
        #expect(r.authors.contains { lib.authors[$0.authorIndex].lastName == "Сандерсон" })
    }

    @Test("Запрос по серии находит серию")
    func seriesMatch() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "Элантрис", language: "ru", in: lib)
        #expect(r.series.contains { lib.series[$0.seriesIndex].name == "Элантрис" })
    }

    @Test("Многословный запрос по книге находит книгу")
    func multiTokenBook() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "понедельник субботу", language: "ru", in: lib)
        #expect(r.books.contains { lib.books[$0.bookIndex].title.contains("Понедельник") })
    }

    @Test("Языковой фильтр исключает книги другого языка из бакета")
    func languageFilter() {
        let lib = Library(
            inpxHash: Data(repeating: 0xAB, count: 32),
            inpxVersion: "v",
            archives: ["arch"],
            authors: [Author.unknown,
                      Author(id: 1, lastName: "Tolstoy", firstName: "Leo", middleName: "")],
            series: [], genres: [],
            books: [
                Book(libid: 1, title: "War and peace", authorIDs: [1],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "en", archiveIndex: 0, size: 0, dateAddedDays: 0),
                Book(libid: 2, title: "Война и мир", authorIDs: [1],
                     seriesID: nil, seriesNum: nil, genreIDs: [],
                     language: "ru", archiveIndex: 0, size: 0, dateAddedDays: 0),
            ]
        )
        let r = SearchEngine.run(query: "война мир", language: "ru", in: lib)
        for m in r.books {
            #expect(lib.books[m.bookIndex].language == "ru")
        }
    }

    @Test("Скоры отсортированы по убыванию во всех бакетах")
    func sortedDescending() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "Элантрис", language: "ru", in: lib)
        #expect(r.books == r.books.sorted { $0.score > $1.score })
        #expect(r.authors == r.authors.sorted { $0.score > $1.score })
        #expect(r.series == r.series.sorted { $0.score > $1.score })
    }

    @Test("Пустой запрос возвращает пустой результат")
    func emptyQuery() {
        let lib = makeLibrary()
        let r = SearchEngine.run(query: "   ", language: "ru", in: lib)
        #expect(r.authors.isEmpty)
        #expect(r.series.isEmpty)
        #expect(r.books.isEmpty)
    }
}

// AuthorMatch / SeriesMatch / BookMatch must be Equatable for `r.books == r.books.sorted`.
extension AuthorMatch: Equatable {
    static func == (lhs: AuthorMatch, rhs: AuthorMatch) -> Bool {
        lhs.authorIndex == rhs.authorIndex && lhs.score == rhs.score
    }
}
extension SeriesMatch: Equatable {
    static func == (lhs: SeriesMatch, rhs: SeriesMatch) -> Bool {
        lhs.seriesIndex == rhs.seriesIndex && lhs.score == rhs.score
    }
}
extension BookMatch: Equatable {
    static func == (lhs: BookMatch, rhs: BookMatch) -> Bool {
        lhs.bookIndex == rhs.bookIndex && lhs.score == rhs.score
    }
}
```

- [ ] **Step 2: Run, expect FAIL (`SearchEngine` не существует)**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/SearchEngine" 2>&1 | tail -30`

- [ ] **Step 3: Реализовать SearchEngine**

Create `FB Loader/FB Loader/Search/SearchEngine.swift`:

```swift
import Foundation

/// Параллельный fuzzy-скан по `Library`. `nonisolated` чтобы можно было
/// вызывать с любого actor'а (в т.ч. из `Task.detached` фоновой задачи).
///
/// Engine не вводит каких-либо собственных лимитов на количество matches —
/// возвращает всё, что прошло `SCORE_CUTOFF`. Пагинация и cap-логика —
/// чисто UI-уровня (см. `SearchCoordinator`/`SearchResultListView`). Это
/// прямо соответствует спеке (§ Группы — «по умолчанию топ-10 + Показать
/// всех»; cap живёт в UI, не в engine).
nonisolated enum SearchEngine {
    static func run(query: String, language: String, in lib: Library) -> SearchResults {
        let qToks = preprocessTokens(query)
        guard !qToks.isEmpty else {
            return SearchResults(authors: [], series: [], books: [])
        }
        let qPatterns = qToks.map(makeLcsPattern)

        // 1. Authors — все matches выше cutoff, отсортированные по убыванию.
        let authorHits = parallelScan(
            qPatterns: qPatterns,
            count: lib.authors.count,
            cutoff: SCORE_CUTOFF
        ) { i in
            lib.searchKeyAuthors[i]
        }
        let authors = authorHits.map { AuthorMatch(authorIndex: $0.index, score: $0.score) }

        // 2. Series
        let seriesHits = parallelScan(
            qPatterns: qPatterns,
            count: lib.series.count,
            cutoff: SCORE_CUTOFF
        ) { i in
            lib.searchKeySeries[i]
        }
        let series = seriesHits.map { SeriesMatch(seriesIndex: $0.index, score: $0.score) }

        // 3. Books — language-filtered, combined key (title + author tokens + series tokens)
        let bookHits = parallelScanBooks(
            qPatterns: qPatterns,
            language: language,
            in: lib,
            cutoff: SCORE_CUTOFF
        )
        let books = bookHits.map { BookMatch(bookIndex: $0.index, score: $0.score) }

        return SearchResults(authors: authors, series: series, books: books)
    }
}

/// Internal scoring hit — индекс в исходном массиве + скор.
/// `nonisolated ... Sendable`: пересекает actor boundary внутри
/// `concurrentPerform` и `Task.detached` (ревью C1).
nonisolated private struct Hit: Sendable {
    let index: Int
    let score: Double
}

/// Generic параллельный скан, отделяет авторов/серии (тут choice — единый
/// массив токенов, доступаемый напрямую по индексу) от книг (где надо
/// объединять title + author + series на лету).
nonisolated private func parallelScan(
    qPatterns: [LcsPattern],
    count: Int,
    cutoff: Double,
    keyAt: (Int) -> [[UInt32]]
) -> [Hit] {
    if count == 0 { return [] }
    let cores = max(2, ProcessInfo.processInfo.activeProcessorCount)
    let chunkSize = (count + cores - 1) / cores
    var perChunk: [[Hit]] = Array(repeating: [], count: cores)
    perChunk.withUnsafeMutableBufferPointer { buf in
        DispatchQueue.concurrentPerform(iterations: cores) { c in
            let lo = c * chunkSize
            let hi = min(lo + chunkSize, count)
            if lo >= hi { return }
            var local: [Hit] = []
            local.reserveCapacity(64)
            for i in lo..<hi {
                let key = keyAt(i)
                let s = tokenMinRatioPre(qPatterns: qPatterns, cTokens: key, cutoff: cutoff)
                if s >= cutoff { local.append(Hit(index: i, score: s)) }
            }
            buf[c] = local
        }
    }
    var hits = perChunk.flatMap { $0 }
    hits.sort { $0.score > $1.score }
    return hits
}

/// Книжный скан с объединением title + author + series tokens на каждой
/// итерации. Доп. фильтр по языку.
nonisolated private func parallelScanBooks(
    qPatterns: [LcsPattern],
    language: String,
    in lib: Library,
    cutoff: Double
) -> [Hit] {
    let n = lib.books.count
    if n == 0 { return [] }
    // Sentinel for "language not specified" matches main-window convention.
    let langKey = language == BooksByContext.unspecifiedLanguageToken ? "" : language
    let cores = max(2, ProcessInfo.processInfo.activeProcessorCount)
    let chunkSize = (n + cores - 1) / cores
    var perChunk: [[Hit]] = Array(repeating: [], count: cores)
    perChunk.withUnsafeMutableBufferPointer { buf in
        DispatchQueue.concurrentPerform(iterations: cores) { c in
            let lo = c * chunkSize
            let hi = min(lo + chunkSize, n)
            if lo >= hi { return }
            var local: [Hit] = []
            local.reserveCapacity(128)
            var combined: [[UInt32]] = []
            combined.reserveCapacity(16)
            for i in lo..<hi {
                if lib.books[i].language != langKey { continue }
                combined.removeAll(keepingCapacity: true)
                combined.append(contentsOf: lib.searchKeyTitle[i])
                let aIdx = Int(lib.searchAuthorIdx[i])
                if aIdx >= 0 {
                    combined.append(contentsOf: lib.searchKeyAuthors[aIdx])
                }
                let sIdx = Int(lib.searchSeriesIdx[i])
                if sIdx >= 0 {
                    combined.append(contentsOf: lib.searchKeySeries[sIdx])
                }
                let s = tokenMinRatioPre(qPatterns: qPatterns, cTokens: combined,
                                         cutoff: cutoff)
                if s >= cutoff { local.append(Hit(index: i, score: s)) }
            }
            buf[c] = local
        }
    }
    var hits = perChunk.flatMap { $0 }
    hits.sort { $0.score > $1.score }
    return hits
}
```

- [ ] **Step 4: Run, expect PASS**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test -only-testing:"FB LoaderTests/SearchEngine" 2>&1 | tail -30`
Expected: 7/7 passes.

- [ ] **Step 5: Полный suite**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test 2>&1 | tail -10`
Expected: всё зелёное.

- [ ] **Step 6: Commit**

```bash
git add "FB Loader/FB Loader/Search/SearchEngine.swift" "FB Loader/FB LoaderTests/SearchEngineTests.swift"
git commit -m "feat(search): add SearchEngine with parallel scoring"
```

---

## Task 7: Refactor LanguageFilterPicker for binding injection

**Files:**
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift` (`LanguageFilterPicker` lines 276-305)
- Modify: `FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift` (call site)

- [ ] **Step 1: Заменить @Environment на Binding параметр**

Edit `BooksTableView.swift`, replace the `LanguageFilterPicker` struct:

```swift
struct LanguageFilterPicker: View {
    let library: Library
    @Binding var selection: String

    var body: some View {
        Picker("", selection: $selection) {
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
        if library.languages.contains("") {
            langs.append(BooksByContext.unspecifiedLanguageToken)
        }
        return langs
    }
    private func label(for code: String) -> String {
        if code == BooksByContext.unspecifiedLanguageToken { return "Не указан" }
        return code.uppercased()
    }
}
```

- [ ] **Step 2: Обновить call site в `LeftSidebarView.swift`**

Find the existing `LanguageFilterPicker(library: library)` call in `LeftSidebarView.swift` (line 20) и заменить на:

```swift
                    LanguageFilterPicker(library: library,
                                         selection: $s.languageFilter)
```

- [ ] **Step 3: Build, expect успех**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run полный suite — поведение не должно поменяться**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test 2>&1 | tail -10`
Expected: всё зелёное.

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift" "FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift"
git commit -m "refactor(ui): inject Binding<String> into LanguageFilterPicker"
```

---

## Task 8: Extract BookRow to standalone with bindings

**Files:**
- Create: `FB Loader/FB Loader/UI/BooksTable/BookRow.swift`
- Modify: `FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift` (удалить приватный struct)

- [ ] **Step 1: Создать самостоятельный BookRow с инжектируемыми bindings**

Create `FB Loader/FB Loader/UI/BooksTable/BookRow.swift`:

```swift
import SwiftUI

/// Standalone book row used by both the main `BooksTableView` (with
/// AppState bindings) and the search window (with local bindings).
struct BookRow: View {
    let book: Book
    let library: Library
    let indented: Bool
    @Binding var isChecked: Bool
    @Binding var isSelected: Bool

    @State private var hovered = false

    static let checkboxWidth: CGFloat = 28
    static let numWidth: CGFloat = 50
    static let sizeWidth: CGFloat = 80
    static let dateWidth: CGFloat = 100
    static let genresWidth: CGFloat = 220

    /// Опциональное контекстное меню. Если nil — меню не отрисовывается.
    var contextMenuBuilder: (() -> AnyView)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isChecked)
                .toggleStyle(.compactCheckbox)
                .labelsHidden()
                .frame(width: BookRow.checkboxWidth, alignment: .center)

            Text(book.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(book.seriesNum.map { "\($0)" } ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: BookRow.numWidth, alignment: .trailing)

            Text(byteCount(book.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: BookRow.sizeWidth, alignment: .trailing)

            Text(date(book.dateAdded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: BookRow.dateWidth, alignment: .trailing)

            Text(genresString)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .frame(width: BookRow.genresWidth, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.leading, indented ? 30 : 16)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
        .background(hovered ? Color.black.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { isSelected = true }
        .modifier(OptionalContextMenu(builder: contextMenuBuilder))
    }

    private func byteCount(_ n: Int32) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
    private func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: d)
    }
    private var genresString: String {
        let names = book.genreIDs.compactMap { library.genreByID[$0]?.name }
        return names.joined(separator: ", ")
    }
}

private struct OptionalContextMenu: ViewModifier {
    let builder: (() -> AnyView)?

    func body(content: Content) -> some View {
        if let builder {
            content.contextMenu { builder() }
        } else {
            content
        }
    }
}
```

- [ ] **Step 2: Удалить приватный `BookRow` из `BooksTableView.swift`**

Удали блок `private struct BookRow: View { ... }` (lines 183-268 в текущем файле).

В оставшемся `BooksTableView`-теле, в `body` ForEach, замени:
```swift
BookRow(book: b, library: library, indented: false)
```
на:
```swift
@Bindable var s = state
BookRow(
    book: b,
    library: library,
    indented: false,
    isChecked: Binding(
        get: { s.checkedBookLibids.contains(b.libid) },
        set: { isOn in
            if isOn { s.checkedBookLibids.insert(b.libid) }
            else    { s.checkedBookLibids.remove(b.libid) }
        }
    ),
    isSelected: Binding(
        get: { s.selectedBookLibid == b.libid },
        set: { _ in s.selectedBookLibid = b.libid }
    ),
    contextMenuBuilder: {
        AnyView(
            Button("Выгрузить отмеченные (\(s.checkedBookLibids.count))") {
                s.shouldStartExport = true
            }
            .disabled(s.checkedBookLibids.isEmpty)
        )
    }
)
```

То же самое для строки в `seriesHeader`-варианте (вторая `BookRow` в файле, теперь `indented: true`).

> **Note:** `@Bindable var s = state` уже стоит снаружи в `var body` — можно его поднять выше, чтобы был доступен в обеих ветках `switch`.

- [ ] **Step 3: Build + run, expect успех**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test 2>&1 | tail -10`
Expected: всё зелёное.

- [ ] **Step 4: Smoke-test в Xcode (открыть приложение, отметить книгу, экспорт работает) — visual check**

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/UI/BooksTable/BookRow.swift" "FB Loader/FB Loader/UI/BooksTable/BooksTableView.swift"
git commit -m "refactor(ui): extract BookRow with injectable bindings"
```

---

## Task 9: SearchCoordinator (window state)

**Files:**
- Create: `FB Loader/FB Loader/Search/SearchCoordinator.swift`

- [ ] **Step 1: Создать coordinator**

Create `FB Loader/FB Loader/Search/SearchCoordinator.swift`:

```swift
import Foundation
import Observation

/// Owns all state for one instance of the search window.
/// Recreated each time the window opens (no persistence).
@Observable
@MainActor
final class SearchCoordinator {
    // Inputs
    var query: String = ""
    /// Local language filter; initialised from main window's `state.languageFilter`
    /// at window-open time, then independent.
    var languageFilter: String

    // Output / status
    var isSearching: Bool = false
    var results: SearchResults? = nil
    var lastQuery: String = ""

    // UI state — local to the window, NOT shared with main `AppState`.
    var checkedBookLibids: Set<Int32> = []
    var selectedBookLibid: Int32? = nil
    /// Per-block collapsed state: keys are author/series indices.
    var collapsedAuthors: Set<Int> = []
    var collapsedSeries: Set<Int> = []
    /// Default visible counts for groups; "Show all" sets to .max.
    var visibleAuthorsCount: Int = 10
    var visibleSeriesCount: Int = 10
    var visibleBooksCount: Int = 20

    init(initialLanguage: String) {
        self.languageFilter = initialLanguage
    }

    /// Запускает поиск. Тяжёлый CPU-bound скан в фоновой задаче, результаты
    /// публикуются на MainActor.
    func runSearch(in library: Library) async {
        let q = query
        if q.trimmingCharacters(in: .whitespaces).isEmpty {
            results = nil
            lastQuery = ""
            return
        }
        isSearching = true
        let lang = languageFilter
        let r = await Task.detached(priority: .userInitiated) {
            SearchEngine.run(query: q, language: lang, in: library)
        }.value
        results = r
        lastQuery = q
        isSearching = false
        // Reset per-result UI state
        collapsedAuthors.removeAll()
        collapsedSeries.removeAll()
        visibleAuthorsCount = 10
        visibleSeriesCount = 10
        visibleBooksCount = 20
        selectedBookLibid = nil
    }
}
```

- [ ] **Step 2: Build verify**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "FB Loader/FB Loader/Search/SearchCoordinator.swift"
git commit -m "feat(search): add SearchCoordinator (window state)"
```

---

## Task 10: SearchWindowView shell + top bar

**Files:**
- Create: `FB Loader/FB Loader/UI/Search/SearchWindowView.swift`

- [ ] **Step 1: Создать корневой View**

Create `FB Loader/FB Loader/UI/Search/SearchWindowView.swift`:

```swift
import SwiftUI

struct SearchWindowView: View {
    let library: Library
    let archivesRoot: URL?
    /// Initial language inherited from main window at open time.
    let initialLanguage: String
    /// Closure to dismiss the sheet — provided by the parent (LeftSidebarView).
    let onClose: () -> Void

    @State private var coord: SearchCoordinator
    /// Search state-id for SwiftUI `.task(id:)` — запускается при изменении.
    @State private var pendingSearchToken: UUID? = nil

    init(library: Library, archivesRoot: URL?, initialLanguage: String,
         onClose: @escaping () -> Void) {
        self.library = library
        self.archivesRoot = archivesRoot
        self.initialLanguage = initialLanguage
        self.onClose = onClose
        _coord = State(initialValue: SearchCoordinator(initialLanguage: initialLanguage))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            content
            Divider()
            detailPanel
        }
        .frame(minWidth: 1000, minHeight: 700)
        .task(id: pendingSearchToken) {
            guard pendingSearchToken != nil else { return }
            await coord.runSearch(in: library)
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let libid = coord.selectedBookLibid,
           let book = library.bookByLibid[libid],
           let archives = archivesRoot {
            BookDetailView(library: library, archivesRoot: archives, book: book)
                .frame(maxWidth: .infinity, minHeight: 380, idealHeight: 420)
        } else {
            Text("Выберите книгу")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: 380, idealHeight: 420)
        }
    }

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 10) {
            TextField("Запрос…", text: $coord.query)
                .textFieldStyle(.roundedBorder)
                .disabled(coord.isSearching)
                .onSubmit { triggerSearch() }
                .frame(maxWidth: .infinity)

            LanguageFilterPicker(library: library, selection: $coord.languageFilter)
                .disabled(coord.isSearching)

            Button(coord.isSearching ? "Поиск…" : "Поиск") {
                triggerSearch()
            }
            .disabled(coord.isSearching || coord.query.trimmingCharacters(in: .whitespaces).isEmpty)
            // Enter в TextField обрабатывается через `.onSubmit { triggerSearch() }`
            // на самом поле — этого достаточно. `.keyboardShortcut(.return)` на
            // кнопке тут добавлять не надо: SwiftUI на macOS отдаёт Enter
            // фокусированному TextField через onSubmit, а второй обработчик на
            // кнопке создаст конкуренцию (двойной запуск или пропуск, по
            // настроению фокуса). Picking one path: onSubmit — единственный
            // путь.

            Button("Закрыть") { onClose() }
                .keyboardShortcut(.cancelAction)   // Escape
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if coord.isSearching {
            VStack(spacing: 12) {
                ProgressView()
                Text("Ищем…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let r = coord.results {
            if r.authors.isEmpty && r.series.isEmpty && r.books.isEmpty {
                Text("По запросу «\(coord.lastQuery)» ничего не найдено")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                SearchResultListView(coord: coord, library: library, results: r)
            }
        } else {
            Text("Введите запрос и нажмите «Поиск»")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func triggerSearch() {
        pendingSearchToken = UUID()
    }
}
```

- [ ] **Step 2: Build verify (`SearchResultListView` ещё не существует — будет ошибка компиляции, временно поставим заглушку)**

Перед коммитом этого таска, добавь в **тот же** файл временный stub:

```swift
struct SearchResultListView: View {
    let coord: SearchCoordinator
    let library: Library
    let results: SearchResults

    var body: some View {
        Text("Список результатов — раздел реализуется в Task 11")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

> Этот stub **обязательно** заменяется в Task 11. Если Task 11 не выполнился — билд имплементации фичи незакончен.

- [ ] **Step 3: Build, expect успех**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add "FB Loader/FB Loader/UI/Search/SearchWindowView.swift"
git commit -m "feat(ui): add SearchWindowView shell with top bar"
```

---

## Task 11: SearchResultListView + group blocks

**Files:**
- Modify: `FB Loader/FB Loader/UI/Search/SearchWindowView.swift` (удалить stub)
- Create: `FB Loader/FB Loader/UI/Search/SearchResultListView.swift`
- Create: `FB Loader/FB Loader/UI/Search/SearchAuthorBlock.swift`
- Create: `FB Loader/FB Loader/UI/Search/SearchSeriesBlock.swift`
- Create: `FB Loader/FB Loader/UI/Search/SearchBooksBucketView.swift`

- [ ] **Step 1: Удалить stub из `SearchWindowView.swift`**

Удали временный `struct SearchResultListView { ... }` в конце `SearchWindowView.swift`.

- [ ] **Step 2: Создать `SearchResultListView`**

Create `FB Loader/FB Loader/UI/Search/SearchResultListView.swift`:

```swift
import SwiftUI

struct SearchResultListView: View {
    let coord: SearchCoordinator
    let library: Library
    let results: SearchResults

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                // Authors group
                if !results.authors.isEmpty {
                    Text("Авторы")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    let visible = results.authors.prefix(coord.visibleAuthorsCount)
                    ForEach(Array(visible.enumerated()), id: \.element.authorIndex) { _, m in
                        SearchAuthorBlock(
                            coord: coord,
                            library: library,
                            authorIndex: m.authorIndex
                        )
                    }
                    if results.authors.count > coord.visibleAuthorsCount {
                        Button("Показать всех (\(results.authors.count))") {
                            coord.visibleAuthorsCount = .max
                        }
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    Divider().padding(.vertical, 6)
                }

                // Series group
                if !results.series.isEmpty {
                    Text("Серии")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                    let visible = results.series.prefix(coord.visibleSeriesCount)
                    ForEach(Array(visible.enumerated()), id: \.element.seriesIndex) { _, m in
                        SearchSeriesBlock(
                            coord: coord,
                            library: library,
                            seriesIndex: m.seriesIndex
                        )
                    }
                    if results.series.count > coord.visibleSeriesCount {
                        Button("Показать все (\(results.series.count))") {
                            coord.visibleSeriesCount = .max
                        }
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    Divider().padding(.vertical, 6)
                }

                // Books bucket
                if !results.books.isEmpty {
                    SearchBooksBucketView(
                        coord: coord,
                        library: library,
                        bookHits: results.books
                    )
                }
            }
        }
    }
}
```

- [ ] **Step 3: Создать `SearchAuthorBlock`**

Create `FB Loader/FB Loader/UI/Search/SearchAuthorBlock.swift`:

```swift
import SwiftUI

/// Один блок «автор &lt;имя&gt;» с книгами этого автора, организованными
/// как в основной таблице (одиночные сначала, потом серии-под-секции).
struct SearchAuthorBlock: View {
    let coord: SearchCoordinator
    let library: Library
    let authorIndex: Int

    private var author: Author { library.authors[authorIndex] }
    private var collapsed: Bool { coord.collapsedAuthors.contains(authorIndex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !collapsed { groupedBooks }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("автор").foregroundStyle(.secondary)
            Text(author.displayName).fontWeight(.semibold)
            Spacer()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if collapsed { coord.collapsedAuthors.remove(authorIndex) }
            else         { coord.collapsedAuthors.insert(authorIndex) }
        }
    }

    @ViewBuilder
    private var groupedBooks: some View {
        let books = BooksByContext.books(for: .author(author.id),
                                         language: coord.languageFilter,
                                         in: library)
        let (loose, bySeries) = groupBooks(books)
        ForEach(Array(loose.enumerated()), id: \.element.libid) { _, b in
            row(for: b, indented: false)
        }
        ForEach(bySeries, id: \.seriesID) { group in
            seriesSubHeader(name: group.seriesName, count: group.books.count)
            ForEach(group.books, id: \.libid) { b in
                row(for: b, indented: true)
            }
        }
    }

    private func row(for b: Book, indented: Bool) -> some View {
        BookRow(
            book: b, library: library, indented: indented,
            isChecked: bindingChecked(b),
            isSelected: bindingSelected(b)
        )
    }

    private func bindingChecked(_ b: Book) -> Binding<Bool> {
        Binding(
            get: { coord.checkedBookLibids.contains(b.libid) },
            set: { isOn in
                if isOn { coord.checkedBookLibids.insert(b.libid) }
                else    { coord.checkedBookLibids.remove(b.libid) }
            }
        )
    }
    private func bindingSelected(_ b: Book) -> Binding<Bool> {
        Binding(
            get: { coord.selectedBookLibid == b.libid },
            set: { _ in coord.selectedBookLibid = b.libid }
        )
    }

    private func seriesSubHeader(name: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(name).font(.system(size: 13, weight: .semibold))
            Text("(\(count))").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private struct SeriesGroup { let seriesID: Int32; let seriesName: String; let books: [Book] }
    private func groupBooks(_ books: [Book]) -> (loose: [Book], series: [SeriesGroup]) {
        var loose: [Book] = []
        var bySeries: [Int32: [Book]] = [:]
        for b in books {
            if let sid = b.seriesID { bySeries[sid, default: []].append(b) }
            else { loose.append(b) }
        }
        let groups: [SeriesGroup] = bySeries
            .sorted { (library.seriesByID[$0.key]?.name ?? "") < (library.seriesByID[$1.key]?.name ?? "") }
            .map { (sid, items) in
                let s = library.seriesByID[sid]
                return SeriesGroup(
                    seriesID: sid,
                    seriesName: s?.name ?? "?",
                    books: items.sorted {
                        ($0.seriesNum ?? Int16.max) < ($1.seriesNum ?? Int16.max)
                    }
                )
            }
        return (loose, groups)
    }
}
```

- [ ] **Step 4: Создать `SearchSeriesBlock`**

Create `FB Loader/FB Loader/UI/Search/SearchSeriesBlock.swift`:

```swift
import SwiftUI

/// Один блок «серия &lt;имя&gt;» — книги серии по `seriesNum`.
struct SearchSeriesBlock: View {
    let coord: SearchCoordinator
    let library: Library
    let seriesIndex: Int

    private var series: Series { library.series[seriesIndex] }
    private var collapsed: Bool { coord.collapsedSeries.contains(seriesIndex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !collapsed { booksList }
        }
    }

    /// Книги серии в текущем языке, отсортированные по `seriesNum`.
    /// Кэшируем тут, чтобы header (для primaryAuthor / count) и body
    /// не пересчитывали два раза.
    private var booksInLanguage: [Book] {
        BooksByContext.books(for: .series(series.id),
                             language: coord.languageFilter,
                             in: library)
            .sorted { ($0.seriesNum ?? Int16.max) < ($1.seriesNum ?? Int16.max) }
    }

    /// «Основной» автор серии — автор её первой книги в выбранном языке.
    private var primaryAuthor: Author? {
        guard let first = booksInLanguage.first,
              let aid = first.authorIDs.first
        else { return nil }
        return library.authorByID[aid]
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("серия").foregroundStyle(.secondary)
            Text(series.name).fontWeight(.semibold)
            Spacer()
            // Спека § Серии: «Справа от заголовка — короткая контекстная
            // строка (имя «основного» автора серии + счётчик «N книг»)».
            if let author = primaryAuthor {
                Text("\(author.displayName) — \(booksCountLabel(booksInLanguage.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if collapsed { coord.collapsedSeries.remove(seriesIndex) }
            else         { coord.collapsedSeries.insert(seriesIndex) }
        }
    }

    private func booksCountLabel(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        let word: String
        if mod100 >= 11 && mod100 <= 14 { word = "книг" }
        else if mod10 == 1 { word = "книга" }
        else if mod10 >= 2 && mod10 <= 4 { word = "книги" }
        else { word = "книг" }
        return "\(n) \(word)"
    }

    @ViewBuilder
    private var booksList: some View {
        let books = booksInLanguage
        ForEach(books, id: \.libid) { b in
            BookRow(
                book: b, library: library, indented: true,
                isChecked: Binding(
                    get: { coord.checkedBookLibids.contains(b.libid) },
                    set: { isOn in
                        if isOn { coord.checkedBookLibids.insert(b.libid) }
                        else    { coord.checkedBookLibids.remove(b.libid) }
                    }
                ),
                isSelected: Binding(
                    get: { coord.selectedBookLibid == b.libid },
                    set: { _ in coord.selectedBookLibid = b.libid }
                )
            )
        }
    }
}
```

- [ ] **Step 5: Создать `SearchBooksBucketView`**

Create `FB Loader/FB Loader/UI/Search/SearchBooksBucketView.swift`:

```swift
import SwiftUI

/// Бакет «Совпадения по книгам» с пагинацией +20.
struct SearchBooksBucketView: View {
    let coord: SearchCoordinator
    let library: Library
    let bookHits: [BookMatch]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Совпадения по книгам")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(bookHits.count) шт")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 4)

            let visible = bookHits.prefix(coord.visibleBooksCount)
            ForEach(Array(visible.enumerated()), id: \.element.bookIndex) { _, m in
                let b = library.books[m.bookIndex]
                BookRow(
                    book: b, library: library, indented: false,
                    isChecked: Binding(
                        get: { coord.checkedBookLibids.contains(b.libid) },
                        set: { isOn in
                            if isOn { coord.checkedBookLibids.insert(b.libid) }
                            else    { coord.checkedBookLibids.remove(b.libid) }
                        }
                    ),
                    isSelected: Binding(
                        get: { coord.selectedBookLibid == b.libid },
                        set: { _ in coord.selectedBookLibid = b.libid }
                    )
                )
            }
            if bookHits.count > coord.visibleBooksCount {
                Button("Загрузить ещё +20") {
                    coord.visibleBooksCount += 20
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}
```

- [ ] **Step 6: Build, expect успех**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add "FB Loader/FB Loader/UI/Search/SearchResultListView.swift" \
        "FB Loader/FB Loader/UI/Search/SearchAuthorBlock.swift" \
        "FB Loader/FB Loader/UI/Search/SearchSeriesBlock.swift" \
        "FB Loader/FB Loader/UI/Search/SearchBooksBucketView.swift" \
        "FB Loader/FB Loader/UI/Search/SearchWindowView.swift"
git commit -m "feat(ui): add search result groups (authors / series / books bucket)"
```

---

## Task 12: Export button + integration with ExportPlanner

**Files:**
- Modify: `FB Loader/FB Loader/UI/Search/SearchWindowView.swift` (добавить toolbar/footer кнопку)

- [ ] **Step 1: Добавить state и кнопку «Экспорт»**

В `SearchWindowView.swift`:

В `@State`-блок добавить:
```swift
@State private var exportProgress: ExportProgress? = nil
```

Перед `.task(id: pendingSearchToken)` добавить footer-bar после `Divider`:

```swift
        VStack(spacing: 0) {
            topBar
            Divider()
            content
            footerBar
            ...
```

И сам footer:
```swift
    @ViewBuilder
    private var footerBar: some View {
        HStack {
            if !coord.checkedBookLibids.isEmpty {
                Text("Отмечено: \(coord.checkedBookLibids.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Экспорт отмеченных") { Task { await runExport() } }
                .disabled(coord.checkedBookLibids.isEmpty || archivesRoot == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
    }
```

И метод (вне body):
```swift
    @MainActor
    private func runExport() async {
        guard !coord.checkedBookLibids.isEmpty,
              let archives = archivesRoot else { return }
        let userPaths = UserPaths.shared
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        // Pre-fill последней папкой экспорта, как в MainWindowView.runExport.
        panel.directoryURL = userPaths.lastExportDirectoryURL
            ?? FileManager.default.urls(for: .downloadsDirectory,
                                        in: .userDomainMask).first
        guard let folder = await panel.selectedDirectory() else { return }
        userPaths.lastExportDirectoryURL = folder

        let items = ExportPlanner.plan(
            libids: coord.checkedBookLibids,
            rootFolder: folder,
            selectedAuthorID: nil,
            selectedSeriesID: nil,
            in: library
        )
        let progress = ExportProgress()
        exportProgress = progress
        Task {
            await ExportRunner.run(items: items, archivesRoot: archives,
                                   library: library, progress: progress)
        }
    }
```

И в конце `body` добавить sheet-биндинг:
```swift
        .sheet(item: Binding(
            get: { exportProgress.map { ProgressIdentifier(progress: $0) } },
            set: { _ in })) { wrapper in
            ExportProgressSheet(progress: wrapper.progress) { exportProgress = nil }
        }
```

И вспомогательный struct в файл (приватный):
```swift
private struct ProgressIdentifier: Identifiable {
    let progress: ExportProgress
    var id: ObjectIdentifier { ObjectIdentifier(progress) }
}
private extension NSOpenPanel {
    @MainActor
    func selectedDirectory() async -> URL? {
        await withCheckedContinuation { c in
            begin { r in c.resume(returning: r == .OK ? self.url : nil) }
        }
    }
}
```

> **Note:** `ProgressIdentifier` и `selectedDirectory()` уже существуют как `private` в `MainWindowView.swift`. Чтобы не дублировать — лучше **поднять в общую видимость**: переименовать в файл `Export/ProgressIdentifier.swift` с `internal` доступом и удалить локальные копии в `MainWindowView` и `SearchWindowView`.
>
> Если делаешь подъём — **дополнительный шаг**: создать файл `FB Loader/FB Loader/Export/ProgressIdentifier.swift`, перенести оба type'а туда, удалить из `MainWindowView.swift` (lines 67-69 и 99-108), обновить commit message.

- [ ] **Step 2: Build, expect успех**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "FB Loader/FB Loader/UI/Search/SearchWindowView.swift"
git commit -m "feat(search): add local export from search window"
```

---

## Task 13: Lupa icon + sheet wiring

**Files:**
- Modify: `FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift`

Поиск открывается как **модальный sheet** поверх главного окна. Никаких отдельных сцен, никакого подъёма `AppState`, никаких lifecycle-edge-кейсов: пока sheet открыт — главное окно блокировано (нельзя зайти в `Настройки`/`Перестроить кэш`/etc.), пока закрыт — sheet'а просто нет. Закрытие — через явную кнопку в sheet'е или клавишу Escape.

- [ ] **Step 1: Добавить кнопку-лупу и `.sheet` в сайдбар**

В `LeftSidebarView.swift`, добавить `@State private var showSearch = false`, кнопку с `magnifyingglass` иконкой в `HStack` перед сегментным `Picker`-ом, и `.sheet(isPresented:)` на корневом `VStack`:

```swift
struct LeftSidebarView: View {
    let library: Library
    @Environment(AppState.self) private var state
    @State private var showSearch = false

    var body: some View {
        @Bindable var s = state
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Поиск по библиотеке")

                    Picker("", selection: $s.sidebarTab) {
                        Text("Авторы").tag(AppState.SidebarTab.authors)
                        Text("Серии").tag(AppState.SidebarTab.series)
                        Text("Жанры").tag(AppState.SidebarTab.genres)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    LanguageFilterPicker(library: library,
                                         selection: $s.languageFilter)
                }

                TextField("Фильтр", text: $s.sidebarFilter)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 12)
            .frame(height: 72)

            // ... остальное тело LeftSidebarView (Divider, switch по sidebarTab, etc.)
            //     — оставляем как есть.
            // ... existing code ...
        }
        .sheet(isPresented: $showSearch) {
            SearchWindowView(
                library: library,
                archivesRoot: state.userPaths.archivesDirectoryURL,
                initialLanguage: state.languageFilter,
                onClose: { showSearch = false }
            )
        }
    }
}
```

> Sheet-приглашённый `SearchWindowView` принимает дополнительный параметр `onClose: () -> Void` (см. правки Task 10 — добавлены) — он вызывается из кнопки «Закрыть» внутри sheet'а и при нажатии Escape.
>
> `archivesRoot` и `initialLanguage` читаются из `state` напрямую при создании sheet'а — никакого подъёма `AppState`, никаких сцен.

- [ ] **Step 2: Build, expect успех**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Smoke test в Xcode**
- Запустить приложение, дождаться загрузки каталога.
- Кликнуть лупу в сайдбаре → sheet «Поиск по библиотеке» появляется поверх главного окна; главное окно блокировано.
- Ввести «Сандерсон», нажать `Поиск` → появляются группы Авторы/Серии/Совпадения по книгам.
- Кликнуть строку книги → деталь книги в нижней панели sheet'a.
- Отметить пару книг → кнопка «Экспорт отмеченных» активна.
- Запустить экспорт из sheet'а → должен появиться **второй sheet** (`ExportProgressSheet`) поверх search-sheet'а, search-sheet остаётся открытым под ним; по завершению экспорта верхний sheet закрывается, поиск снова в фокусе.
- Нажать `Escape` или кнопку `Закрыть` → sheet закрывается, главное окно снова доступно.
- Повторно открыть лупой → sheet чистый (новый `SearchCoordinator`), без сохранённого предыдущего состояния (это особенность sheet — каждый показ инстанцирует контент заново).
- Проверить, что главное окно ≥ 1000×700 — если у пользователя меньше, sheet может выглядеть тесно (sheet с `.frame(minWidth: 1000, minHeight: 700)` подгоняется под parent window). Для v1 это «known good enough», полное responsive-поведение — потом.
- Sanity-check: открыт sheet → главное окно блокировано → пункт «Настройки → Перестроить кэш» в системе **недоступен** пока sheet наверху. Это проверяется визуально: попробовать активировать main-окно мышью / cmd-tab — фокус не должен переходить, либо переходить только после закрытия sheet'а. (Этот пункт — следствие модальности sheet'а, edge-case с реимпортом во время поиска у нас не возникает по построению.)

- [ ] **Step 4: Run полный test-suite — ничего не сломали**

Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test 2>&1 | tail -10`
Expected: всё зелёное.

- [ ] **Step 5: Commit**

```bash
git add "FB Loader/FB Loader/UI/LeftSidebar/LeftSidebarView.swift"
git commit -m "feat(search): wire lupa button and search sheet"
```

> `SearchWindowView.swift` правится в Task 10 (init + onClose) и Task 12 (export sheet) — здесь не пересоздаём, поэтому в `git add` не включаем.

---

## Task 14: bd close + acceptance verification

**Files:** none (housekeeping)

- [ ] **Step 1: Smoke по acceptance criteria из спеки**

Пройдись по `docs/superpowers/specs/2026-05-04-fuzzy-search-design.md` § Acceptance criteria, проверь все пункты:

- [x] Лупа в сайдбаре открывает «Поиск по библиотеке».
- [x] В окне: поле, языковой пикер (наследует значение от главного окна), кнопка «Поиск».
- [x] Триггер только по кнопке/Enter.
- [x] Три группы (Авторы / Серии / Совпадения по книгам).
- [x] Заголовки авторов/серий с collapse, по умолчанию развёрнуты.
- [x] «Показать всех» / «Показать все» / «Загрузить ещё +20» работают.
- [x] Под автором — структура основной таблицы; под серией — по `seriesNum`.
- [x] Языковой фильтр окна применяется к книгам авторов/серий.
- [x] Клик по строке книги → деталь снизу.
- [x] Чекбоксы локальные, кнопка «Экспорт» в окне.
- [x] 13/13 кейсов корпуса fuzzy-скорера.
- [x] Cross-check `lcsLengthDP ≡ lcsLengthBP`.
- [x] Время отклика на каталоге 580k книг — ≤500 мс.

- [ ] **Step 2: Запустить приложение на реальном кэше, замерить время**

Открыть Xcode-debug session, запустить, зайти в окно поиска, ввести «Сандерсон» → нажать «Поиск». В консоли должны появиться `[Library.init] ...` логи (на холодном старте).

Удержать что отклик «по ощущению» в районе сотни-двух миллисекунд (не считая холодной сборки индекса при загрузке).

- [ ] **Step 3: Закрыть beads issue**

```bash
bd close fb-loader-73t --reason "Implemented per docs/superpowers/specs/2026-05-04-fuzzy-search-design.md and plans/2026-05-04-fuzzy-search.md. Acceptance criteria verified, 13/13 corpus pass, ≤500ms on 581k books."
```

- [ ] **Step 4: Финальный verify**

Run: `git status` → `nothing to commit, working tree clean`.
Run: `xcodebuild -project "FB Loader/FB Loader.xcodeproj" -scheme "FB Loader" -destination "platform=macOS" test 2>&1 | tail -10` → всё зелёное.

- [ ] **Step 5: НЕ пушить.** Без явного «push» от пользователя — стоп. Сообщить через TG что готово, и попросить ОК на push.

---

## Self-Review Checklist

После того как все таски пройдены:

- [ ] Спека покрыта целиком: каждая секция в спеке имеет соответствующий task.
- [ ] Никаких placeholder'ов (TODO/TBD/«similar to Task N»).
- [ ] Имена методов и типов согласованы между тасками (`tokenMinRatio` vs `tokenMinRatioPre`, `LcsPattern` единственная форма, `SearchEngine.run` единственная entry-point).
- [ ] Все tests/файлы в Xcode-target включились автоматически (`PBXFileSystemSynchronizedRootGroup`).
- [ ] Корпус fuzzy-скорера прошёл 13/13.
- [ ] Cross-check `DP ≡ BP` зелёный.
- [ ] Smoke test в реальном UI прошёл.
