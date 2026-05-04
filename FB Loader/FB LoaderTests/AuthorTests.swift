import Testing
@testable import FB_Loader

@Suite("Author")
struct AuthorTests {
    @Test("displayName собирается из непустых компонентов через пробел")
    func displayNameFull() {
        let a = Author(id: 1, lastName: "Толстой", firstName: "Лев", middleName: "Николаевич")
        #expect(a.displayName == "Толстой Лев Николаевич")
    }

    @Test("displayName пропускает пустые компоненты")
    func displayNamePartial() {
        let a = Author(id: 2, lastName: "Кинг", firstName: "Стивен", middleName: "")
        #expect(a.displayName == "Кинг Стивен")
    }

    @Test("displayName равен 'placeholder' для псевдо-автора без полей")
    func displayNameEmptyUsesPlaceholder() {
        let a = Author.unknown
        #expect(a.displayName == "(Без автора)")
    }
}
