import Foundation

enum BooksByContext {
    enum Context { case author(Int32), series(Int32), genre(Int16) }
    /// Sentinel token used in the language filter to mean "language not set in INPX".
    static let unspecifiedLanguageToken = "__none__"

    static func books(for ctx: Context, language: String, in lib: Library) -> [Book] {
        let indices: [Int]
        switch ctx {
        case .author(let id): indices = lib.booksByAuthor[id] ?? []
        case .series(let id): indices = lib.booksBySeries[id] ?? []
        case .genre(let id): indices = lib.booksByGenre[id] ?? []
        }
        let langKey: String
        if language == unspecifiedLanguageToken { langKey = "" }
        else { langKey = language }
        return indices.compactMap { i in
            let b = lib.books[i]
            return b.language == langKey ? b : nil
        }
    }
}
