import Testing
import Foundation
@testable import FB_Loader

@Suite("RussianPlural")
struct RussianPluralTests {
    @Test("склонение «книга/книги/книг»", arguments: [
        (1, "1 книга"), (2, "2 книги"), (5, "5 книг"), (11, "11 книг"), (12, "12 книг"),
        (14, "14 книг"), (21, "21 книга"), (22, "22 книги"), (25, "25 книг"),
        (101, "101 книга"), (111, "111 книг"), (0, "0 книг"),
    ])
    func books(n: Int, expected: String) {
        #expect(booksCountLabel(n) == expected)
    }
}
