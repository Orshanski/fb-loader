import Foundation

/// Русское склонение: 1 книга, 2 книги, 5 книг (11–14 — всегда «много»).
nonisolated func russianPlural(_ n: Int, one: String, few: String, many: String) -> String {
    let mod10 = n % 10
    let mod100 = n % 100
    let word: String
    if mod100 >= 11 && mod100 <= 14 { word = many }
    else if mod10 == 1 { word = one }
    else if mod10 >= 2 && mod10 <= 4 { word = few }
    else { word = many }
    return "\(n) \(word)"
}

nonisolated func booksCountLabel(_ n: Int) -> String {
    russianPlural(n, one: "книга", few: "книги", many: "книг")
}
