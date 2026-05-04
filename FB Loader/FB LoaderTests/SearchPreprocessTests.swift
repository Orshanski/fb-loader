import Testing
import Foundation
@testable import FB_Loader

@Suite("SearchPreprocess")
struct SearchPreprocessTests {
    // MARK: - decoding helpers

    private func decode(_ token: [UInt32]) -> String {
        // Force-unwrap is intentional: scalars come from preprocessTokens,
        // which always emits valid `Unicode.Scalar`-convertible values.
        // A nil here is a bug in `tokens(_:)` — we want the test to crash.
        String(String.UnicodeScalarView(token.compactMap { Unicode.Scalar($0) }))
    }

    private func decode(_ tokens: [[UInt32]]) -> [String] {
        tokens.map(decode)
    }

    // MARK: - corpus

    @Test("Пустая строка → пустой массив токенов")
    func empty() {
        #expect(SearchPreprocess.tokens("") == [])
    }

    @Test("Простое слово ASCII → один токен в нижнем регистре")
    func asciiWord() {
        let toks = SearchPreprocess.tokens("Hello")
        #expect(decode(toks) == ["hello"])
    }

    @Test("Кириллица в нижнем регистре")
    func cyrillicLowercase() {
        let toks = SearchPreprocess.tokens("Сандерсон")
        #expect(decode(toks) == ["сандерсон"])
    }

    @Test("ё → е, Ё → е (в начале слова)")
    func yoToYeAtStart() {
        #expect(decode(SearchPreprocess.tokens("ёлка")) == ["елка"])
        #expect(decode(SearchPreprocess.tokens("Ёлка")) == ["елка"])
    }

    @Test("ё/Ё в середине слова тоже сворачиваются")
    func yoToYeMidWord() {
        #expect(decode(SearchPreprocess.tokens("привЁт")) == ["привет"])
        #expect(decode(SearchPreprocess.tokens("приЁмник")) == ["приемник"])
    }

    @Test("Пунктуация и пробелы — разделители токенов, схлопываются")
    func punctuationSplits() {
        let toks = SearchPreprocess.tokens("Война и мир!  ")
        #expect(decode(toks) == ["война", "и", "мир"])
    }

    @Test("Только разделители → пустой результат")
    func onlySeparators() {
        #expect(SearchPreprocess.tokens("  --  ") == [])
        #expect(SearchPreprocess.tokens("!?,.;:") == [])
    }

    @Test("Один символ — один токен")
    func singleChar() {
        #expect(decode(SearchPreprocess.tokens("я")) == ["я"])
        #expect(decode(SearchPreprocess.tokens("a")) == ["a"])
    }

    @Test("Цифры сохраняются")
    func digitsKept() {
        #expect(decode(SearchPreprocess.tokens("1984")) == ["1984"])
    }

    @Test("Микс ASCII и кириллицы и цифр в одном слове")
    func mixedScript() {
        #expect(decode(SearchPreprocess.tokens("ABC123фыв")) == ["abc123фыв"])
    }

    @Test("Цифры в середине кириллического слова не разрывают токен")
    func digitsMidCyrillic() {
        #expect(decode(SearchPreprocess.tokens("часть2глава5")) == ["часть2глава5"])
    }

    @Test("Тире и табы — разделители")
    func dashTabAreSeparators() {
        let toks = SearchPreprocess.tokens("foo-bar\tbaz")
        #expect(decode(toks) == ["foo", "bar", "baz"])
    }

    @Test("Surrogate / emoji — разделитель, не разрывает алфавитные слова")
    func emojiSeparator() {
        let toks = SearchPreprocess.tokens("a😀b")
        #expect(decode(toks) == ["a", "b"])
    }

    @Test("Украинская кириллица (і, ї, є, ґ) считается буквой")
    func ukrainianCyrillic() {
        // Сначала проверяем, что украинско-специфичные буквы вообще
        // распознаются как алфавитные (не разрывают токен).
        let cont = SearchPreprocess.tokens("Україна")
        #expect(cont.count == 1, "слово 'Україна' должно остаться одним токеном, не порезаться на 'кра' + 'на'")

        // Залочка асимметрии: lowercase-блок сворачивает только А..Я
        // (U+0410..U+042F), поэтому заглавная Ї (U+0407) остаётся в
        // верхнем регистре, а Ж/А/К — лоуэркейсятся.
        let toks = SearchPreprocess.tokens("ЇЖАК")
        #expect(toks.count == 1)
        #expect(decode(toks[0]) == "Їжак",
                "Ї остаётся в верхнем регистре — преобразуем только А..Я")
    }

    @Test("Латиница с диакритикой считается буквой")
    func latinDiacritics() {
        let toks = SearchPreprocess.tokens("naïve")
        #expect(toks.count == 1)
        // ï остаётся в исходной форме (не ASCII A..Z).
        #expect(decode(toks[0]) == "naïve")
    }
}
