import Testing
import Foundation
@testable import FB_Loader

@Suite("FuzzyScorer corpus")
struct FuzzyScorerCorpusTests {
    /// Эталонные пары из `librarium-py/backend/app/search.py`
    /// (комментарий к `_token_match_score`) + edge-кейсы по нормализации.
    /// Любая регрессия здесь — баг.
    static let corpus: [(q: String, c: String, pass: Bool, label: String)] = [
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
            let qTokens = SearchPreprocess.tokens(tc.q)
            let cTokens = SearchPreprocess.tokens(tc.c)
            let score = FuzzyScorer.tokenMinRatio(qTokens: qTokens, cTokens: cTokens)
            let actualPass = score >= FuzzyScorer.SCORE_CUTOFF
            #expect(actualPass == tc.pass,
                    "\(tc.label): \(tc.q) → \(tc.c) — score \(score), expected \(tc.pass ? "≥75" : "<75")")
        }
    }

    @Test("Пустые входы дают 0")
    func emptyInputs() {
        #expect(FuzzyScorer.tokenMinRatio(qTokens: [], cTokens: [[0x61]]) == 0)
        #expect(FuzzyScorer.tokenMinRatio(qTokens: [[0x61]], cTokens: []) == 0)
    }

    @Test("SCORE_CUTOFF равен 75")
    func cutoffConstant() {
        #expect(FuzzyScorer.SCORE_CUTOFF == 75.0)
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
}

@Suite("FuzzyScorer bit-parallel")
struct FuzzyScorerBPTests {
    /// Все пары из корпуса + дополнительные ровно для cross-check.
    static let pairs: [(q: String, c: String)] = [
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
            let qToks = SearchPreprocess.tokens(q)
            let cToks = SearchPreprocess.tokens(c)
            for qt in qToks {
                for ct in cToks {
                    let dp = FuzzyScorer.lcsLengthDP(qt, ct)
                    let bp = FuzzyScorer.lcsLengthBP(qt, ct)
                    #expect(dp == bp, "\(q) × \(c): DP=\(dp), BP=\(bp)")
                }
            }
        }
    }

    @Test("Pre-built scorer даёт те же скоры, что и не-pre-built вариант")
    func preBuiltMatchesNaive() {
        for tc in FuzzyScorerCorpusTests.corpus {
            let qToks = SearchPreprocess.tokens(tc.q)
            let cToks = SearchPreprocess.tokens(tc.c)
            let naive = FuzzyScorer.tokenMinRatio(qTokens: qToks, cTokens: cToks)
            let qPatterns = qToks.map(FuzzyScorer.LcsPattern.init)
            let pre = FuzzyScorer.tokenMinRatioPre(
                qPatterns: qPatterns, cTokens: cToks,
                cutoff: FuzzyScorer.SCORE_CUTOFF
            )
            // Pre с cutoff может вернуть 0 раньше naive — но именно когда
            // `naive < cutoff`. В остальных случаях должны совпадать.
            if naive >= FuzzyScorer.SCORE_CUTOFF {
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
        let qToks = SearchPreprocess.tokens(longPat)
        let cToks = SearchPreprocess.tokens(target)
        let qPatterns = qToks.map(FuzzyScorer.LcsPattern.init)
        #expect(qPatterns[0].isLong == true)
        // LCS должен быть 1: "а" есть один раз в обеих строках, и "а"
        // покрывается из паттерна длины 70.
        #expect(FuzzyScorer.lcsLengthPre(qPatterns[0], cToks[0]) == 1)
    }
}
