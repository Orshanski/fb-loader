import Testing
@testable import FB_Loader

@Suite("Author")
struct AuthorTests {
    @Test("displayName собирается из непустых компонентов через пробел")
    func displayName_full() {
        let a = Author(id: 1, lastName: "Толстой", firstName: "Лев", middleName: "Николаевич")
        #expect(a.displayName == "Толстой Лев Николаевич")
    }

    @Test("displayName пропускает пустые компоненты")
    func displayName_partial() {
        let a = Author(id: 2, lastName: "Кинг", firstName: "Стивен", middleName: "")
        #expect(a.displayName == "Кинг Стивен")
    }

    @Test("displayName равен 'placeholder' для псевдо-автора без полей")
    func displayName_empty_uses_placeholder() {
        let a = Author.unknown
        #expect(a.displayName == "(Без автора)")
    }
}
