import Testing
import Foundation
@testable import FB_Loader

@Suite("SearchPreprocess")
struct SearchPreprocessTests {
    // MARK: - decoding helpers

    private func decode(_ token: [UInt32]) -> String {
        // Force-via-compactMap is intentional: scalars come from
        // `SearchPreprocess.tokens(_:)`, which always emits valid
        // `Unicode.Scalar`-convertible values. A nil here would be a bug
        // in `tokens(_:)` — we want it visible at decode time.
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

    @Test("Украинская кириллица (і, ї, є, ґ) считается буквой и приводится к нижнему регистру")
    func ukrainianCyrillic() {
        let cont = SearchPreprocess.tokens("Україна")
        #expect(cont.count == 1, "слово 'Україна' должно остаться одним токеном, не порезаться на 'кра' + 'на'")

        let toks = SearchPreprocess.tokens("ЇЖАК")
        #expect(toks.count == 1)
        #expect(decode(toks[0]) == "їжак")
        #expect(SearchPreprocess.tokens("Іван") == SearchPreprocess.tokens("іван"))
    }

    @Test("Нижний регистр для любой письменности", arguments: [
        ("ŁÓDŹ", "łódź"), ("ÉCOLE", "école"), ("ΑΘΗΝΑ", "αθηνα"), ("ЎСЁ", "ўсе"), ("Ђорђе", "ђорђе")])
    func lowercaseAnyScript(_ raw: String, _ expected: String) {
        #expect(decode(SearchPreprocess.tokens(raw)) == [expected])
    }

    @Test("Разложенная «e + U+0301» совпадает с составной «é»")
    func decomposedEqualsPrecomposed() {
        let decomposed = SearchPreprocess.tokens("e\u{301}cole Pe\u{301}rez")
        #expect(decomposed == SearchPreprocess.tokens("\u{E9}cole P\u{E9}rez"))
        #expect(decode(decomposed) == ["\u{E9}cole", "p\u{E9}rez"])
        #expect(SearchPreprocess.tokens("Йе\u{308}ж") == SearchPreprocess.tokens("Йеж"),
                "разложенная ё тоже сворачивается в е")
    }

    @Test("Латиница с диакритикой считается буквой")
    func latinDiacritics() {
        let toks = SearchPreprocess.tokens("naïve")
        #expect(toks.count == 1)
        // ï остаётся в исходной форме (не ASCII A..Z).
        #expect(decode(toks[0]) == "naïve")
    }
}
