import Testing
@testable import FB_Loader

@Suite("NamePattern")
struct NamePatternTests {
    // MARK: - parsing

    @Test("Пустой и пробельный запрос → .all")
    func emptyQuery() {
        #expect(NamePattern(query: "") == .all)
        #expect(NamePattern(query: "   ") == .all)
    }

    @Test("Запрос из одних звёздочек → .all")
    func starsOnlyCollapseToAll() {
        #expect(NamePattern(query: "*") == .all)
        #expect(NamePattern(query: "***") == .all)
    }

    @Test("Без звёздочки парсится как wordPrefix и приводится к нижнему регистру")
    func plainParsesAsWordPrefix() {
        #expect(NamePattern(query: "Олди") == .wordPrefix("олди"))
        #expect(NamePattern(query: "  ОЛДИ  ") == .wordPrefix("олди"))
    }

    @Test("Звёздочка в любой позиции переключает в .glob с правильными якорями")
    func globAnchors() {
        #expect(NamePattern(query: "пет*") == .glob(segments: ["пет"], anchorStart: true, anchorEnd: false))
        #expect(NamePattern(query: "*пет") == .glob(segments: ["пет"], anchorStart: false, anchorEnd: true))
        #expect(NamePattern(query: "*пет*") == .glob(segments: ["пет"], anchorStart: false, anchorEnd: false))
        #expect(NamePattern(query: "пет*ров") == .glob(segments: ["пет", "ров"], anchorStart: true, anchorEnd: true))
    }

    // MARK: - word prefix matching (the Олди / Болдин case)

    @Test("Словесный префикс находит начало строки")
    func wordPrefixMatchesStringStart() {
        let p = NamePattern(query: "олди")
        #expect(p.matches("олди"))
        #expect(p.matches("олдисс"))
    }

    @Test("Словесный префикс находит начало слова после пробела или пунктуации")
    func wordPrefixMatchesAfterBoundary() {
        let p = NamePattern(query: "лев")
        #expect(p.matches("толстой лев николаевич"))
        let q = NamePattern(query: "олди")
        #expect(q.matches("г.л. олди"))
        #expect(q.matches("г.л.олди"))
    }

    @Test("Словесный префикс НЕ совпадает с серединой слова")
    func wordPrefixRejectsMidWord() {
        let p = NamePattern(query: "олди")
        #expect(!p.matches("болдин"))
        #expect(!p.matches("колдин"))
    }

    @Test("Словесный префикс на пустой строке — false")
    func wordPrefixOnEmptyName() {
        #expect(!NamePattern(query: "олди").matches(""))
    }

    // MARK: - glob matching

    @Test("Префиксный glob (пет*) якорит начало строки")
    func globPrefix() {
        let p = NamePattern(query: "пет*")
        #expect(p.matches("петров"))
        #expect(p.matches("петя"))
        #expect(!p.matches("выпет"))
        #expect(!p.matches("васипетров"))
    }

    @Test("Суффиксный glob (*ров) якорит конец строки")
    func globSuffix() {
        let p = NamePattern(query: "*ров")
        #expect(p.matches("петров"))
        #expect(p.matches("ров"))
        #expect(!p.matches("ровно"))
    }

    @Test("Substring-glob (*пет*) находит любое вхождение, без word boundary")
    func globSubstring() {
        let p = NamePattern(query: "*олди*")
        #expect(p.matches("олди"))
        #expect(p.matches("олдисс"))
        #expect(p.matches("болдин"))             // именно тут glob отличается от word-prefix:
        #expect(p.matches("гл олди и компания")) // в substring-режиме «болдин» матчится.
        #expect(p.matches("xxxолдиyyy"))
        #expect(!p.matches("вася"))
    }

    @Test("Glob с двумя сегментами (пет*ров) требует порядка и якорей")
    func globTwoSegments() {
        let p = NamePattern(query: "пет*ров")
        #expect(p.matches("петров"))
        #expect(p.matches("петяров"))
        #expect(p.matches("петрович ров"))
        #expect(!p.matches("ровпет"))
        #expect(!p.matches("петровский"))
        #expect(!p.matches("апетров"))
    }

    @Test("Двойная звёздочка эквивалентна одинарной")
    func doubleStarCollapses() {
        let p = NamePattern(query: "пет**ров")
        #expect(p.matches("петров"))
        #expect(p.matches("пет ров"))
    }

    @Test("Glob с регистром: запрос приводится к нижнему")
    func globLowercasing() {
        let p = NamePattern(query: "ОЛД*")
        #expect(p.matches("олди"))
    }
}
