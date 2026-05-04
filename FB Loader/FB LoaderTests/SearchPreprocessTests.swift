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
