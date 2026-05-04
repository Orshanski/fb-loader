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
}
