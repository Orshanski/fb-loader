import Testing
@testable import FB_Loader

@Suite("INPAuthorParser")
struct INPAuthorParserTests {
    @Test("parses single author with three components")
    func single() {
        let r = INPAuthorParser.parse("Толстой,Лев,Николаевич")
        #expect(r.count == 1)
        #expect(r[0].lastName == "Толстой")
        #expect(r[0].firstName == "Лев")
        #expect(r[0].middleName == "Николаевич")
    }

    @Test("parses multiple authors separated by colon")
    func multiple() {
        let r = INPAuthorParser.parse("Дяченко,Марина,:Дяченко,Сергей,:Олди,Генри,Лайон")
        #expect(r.count == 3)
        #expect(r[0].lastName == "Дяченко")
        #expect(r[2].lastName == "Олди")
        #expect(r[2].middleName == "Лайон")
    }

    @Test("trims whitespace; missing components are empty strings")
    func sparse() {
        let r = INPAuthorParser.parse("Кинг,Стивен,")
        #expect(r.count == 1)
        #expect(r[0].lastName == "Кинг")
        #expect(r[0].firstName == "Стивен")
        #expect(r[0].middleName == "")
    }

    @Test("returns empty array for empty input")
    func empty() {
        #expect(INPAuthorParser.parse("") == [])
    }

    @Test("isUnknown detects common 'автор неизвестен' phrasings")
    func unknownDetection() {
        #expect(INPAuthorParser.isUnknown(lastName: "Автор", firstName: "Неизвестен", middleName: ""))
        #expect(INPAuthorParser.isUnknown(lastName: "автор", firstName: "неизвестный", middleName: ""))
        #expect(INPAuthorParser.isUnknown(lastName: "Неизвестно", firstName: "", middleName: ""))
        #expect(!INPAuthorParser.isUnknown(lastName: "Толстой", firstName: "Лев", middleName: "Николаевич"))
    }
}
