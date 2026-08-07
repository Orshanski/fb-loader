import Foundation

/// `nonisolated` всему enum — все его члены пользуются нонизолированными
/// контекстами (sidebar list, BooksTableView body, SearchEngine
/// `parallelScanBooks` worker thread). Без этой пометки под
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` enum и его статики
/// автоматически становятся MainActor-isolated, и доступ из nonisolated
/// контекста (особенно из `concurrentPerform`-worker'а в SearchEngine)
/// ловит warning «main actor-isolated property … referenced from a
/// nonisolated context».
nonisolated enum BooksByContext {
    enum Context { case author(Int32), series(Int32), genre(Int16) }
    /// Sentinel token used in the language filter to mean "language not set in INPX".
    static let unspecifiedLanguageToken = "__none__"

    static func books(for ctx: Context,
                      language: String,
                      dates: DateRangeFilter? = nil,
                      in lib: Library) -> [Book] {
        booksWithTotal(for: ctx, language: language, dates: dates, in: lib).books
    }

    /// Отобранные книги плюс сколько их всего в этом контексте и языке —
    /// числитель и знаменатель для «12 из 264».
    ///
    /// Обе величины считаются одним проходом и по одному и тому же
    /// множеству. Отдельный предпосчитанный счётчик для знаменателя дал бы
    /// расхождение на книгах, которые фильтр отбрасывает по причинам, о
    /// которых счётчик не знает.
    static func booksWithTotal(for ctx: Context,
                               language: String,
                               dates: DateRangeFilter?,
                               in lib: Library) -> (books: [Book], total: Int) {
        let indices: [Int]
        switch ctx {
        case .author(let id): indices = lib.booksByAuthor[id] ?? []
        case .series(let id): indices = lib.booksBySeries[id] ?? []
        case .genre(let id): indices = lib.booksByGenre[id] ?? []
        }
        let langKey = languageKey(language)
        var out: [Book] = []
        out.reserveCapacity(indices.count)
        var total = 0
        for i in indices {
            let b = lib.books[i]
            guard b.language == langKey else { continue }
            total += 1
            if let dates, !dates.contains(b) { continue }
            out.append(b)
        }
        return (out, total)
    }

    /// Sentinel «Не указан» → пустая строка, под которой язык лежит и в
    /// `Book.language`, и ключом в `bookCountBy*ByLang`.
    private static func languageKey(_ language: String) -> String {
        language == unspecifiedLanguageToken ? "" : language
    }
}
