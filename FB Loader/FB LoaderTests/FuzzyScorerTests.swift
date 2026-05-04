import Testing
import Foundation
@testable import FB_Loader

@Suite("FuzzyScorer corpus")
struct FuzzyScorerCorpusTests {
    /// Эталонные пары: librarium-py corpus + edge-кейсы по нормализации +
    /// false-positive'ы из реальной библиотеки на 167k авторов, отловленные
    /// при ручной проверке (см. spike4 в `~/code/fb-loader-search-spike`).
    /// Любая регрессия здесь — баг.
    static let corpus: [(q: String, c: String, pass: Bool, label: String)] = [
        // librarium corpus
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
        // user-flagged false positives — должны отсеиваться
        ("сандерсо", "Андерсон", false, "ФП: edge subs"),
        ("сандерсо", "Андросов", false, "ФП: разные имена"),
        ("сандерсо", "Сандерсон", true, "Sanderson корректно"),
        ("Толстой", "Толстиков", false, "ФП: разные фамилии"),
        ("Достоевский", "Островский", false, "ФП: разные фамилии"),
        ("Достоевский", "Гостковский", false, "ФП: разные фамилии"),
        ("Махабрахата", "Махабхарата", true, "опечатка-транспозиция"),
    ]

    @Test("Эталонные пары корректно ранжируются")
    func corpusFullPass() {
        for tc in Self.corpus {
            let qTokens = SearchPreprocess.tokens(tc.q)
            let cTokens = SearchPreprocess.tokens(tc.c)
            let score = FuzzyScorer.tokenMinRatio(qTokens: qTokens, cTokens: cTokens)
            let actualPass = score >= FuzzyScorer.SCORE_CUTOFF
            #expect(actualPass == tc.pass,
                    "\(tc.label): \(tc.q) → \(tc.c) — score \(score), expected \(tc.pass ? "≥83" : "<83")")
        }
    }

    @Test("Пустые входы дают 0")
    func emptyInputs() {
        #expect(FuzzyScorer.tokenMinRatio(qTokens: [], cTokens: [[0x61]]) == 0)
        #expect(FuzzyScorer.tokenMinRatio(qTokens: [[0x61]], cTokens: []) == 0)
    }

    @Test("SCORE_CUTOFF равен 83")
    func cutoffConstant() {
        #expect(FuzzyScorer.SCORE_CUTOFF == 83.0)
    }

    @Test("Идентичные одинаковые входы дают 100.0")
    func identicalInputsScore100() {
        // ASCII single-token
        let asciiTok = SearchPreprocess.tokens("hello")
        #expect(FuzzyScorer.tokenMinRatio(qTokens: asciiTok, cTokens: asciiTok) == 100.0)
        // Cyrillic single-token
        let cyrTok = SearchPreprocess.tokens("сандерсон")
        #expect(FuzzyScorer.tokenMinRatio(qTokens: cyrTok, cTokens: cyrTok) == 100.0)
        // Multi-token, same tokens, same order
        let multi = SearchPreprocess.tokens("война и мир")
        #expect(FuzzyScorer.tokenMinRatio(qTokens: multi, cTokens: multi) == 100.0)
    }

    @Test("Один query-токен против многотокенного choice — score = best per-token match")
    func singleQueryVsMultiChoice() {
        let q = SearchPreprocess.tokens("сандерсон")
        let c = SearchPreprocess.tokens("брэндон сандерсон писатель")
        let score = FuzzyScorer.tokenMinRatio(qTokens: q, cTokens: c)
        // q.first matches c.second perfectly → 100.0
        #expect(score == 100.0)
    }

    @Test("Многотокенный query против одного choice-токена — оба должны найтись или score падает")
    func multiQueryVsSingleChoice() {
        // Choice — одно слово; query — два. Оба query-токена ищут лучший
        // матч в одном-единственном c-токене. Один совпадёт идеально,
        // другой даст слабый — итоговый min будет слабым.
        let q = SearchPreprocess.tokens("сандерсон писатель")
        let c = SearchPreprocess.tokens("сандерсон")
        let score = FuzzyScorer.tokenMinRatio(qTokens: q, cTokens: c)
        // «писатель» против «сандерсон» — низкий скор → итоговый min < cutoff
        #expect(score < FuzzyScorer.SCORE_CUTOFF,
                "score=\(score), expected below cutoff \(FuzzyScorer.SCORE_CUTOFF)")
    }

    @Test("Транспозиция считается одной операцией")
    func transpositionCountsAsSingleOp() {
        // ОSA Damerau-Levenshtein учитывает adjacent-транспозицию как 1 op,
        // а не 2 substitution. «ab» ↔ «ba» имеет distance 1, а не 2.
        let q: [UInt32] = [97, 98]              // "ab"
        let c: [UInt32] = [98, 97]              // "ba"
        let d = FuzzyScorer.damerauLevenshteinOSA(q, c)
        #expect(d == 1, "DL(ab, ba) = \(d), expected 1 (transposition)")
    }

    @Test("Cutoff-pruning возвращает 0 если хоть один qt не дотягивает до cutoff")
    func cutoffPruningEarlyExit() {
        // q = ["сандерсон", "хххх"] — второй токен не имеет хорошего матча
        // нигде в c. Финальный min будет ниже cutoff, метод должен вернуть 0
        // не дойдя до конца.
        let q = SearchPreprocess.tokens("сандерсон хххх")
        let c = SearchPreprocess.tokens("брэндон сандерсон писатель")
        let pruned = FuzzyScorer.tokenMinRatioCut(
            qTokens: q, cTokens: c, cutoff: FuzzyScorer.SCORE_CUTOFF)
        #expect(pruned == 0, "expected pruning to return 0, got \(pruned)")
    }
}
