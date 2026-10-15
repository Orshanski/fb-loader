import Foundation

/// Один буфер вместо массива на слово: заголовки и запас ёмкости миллионов
/// мелких массивов занимали в разы больше самих символов.
/// 16 бит на символ вдвое дешевле 32; символы вне BMP сводятся к U+FFFD — одинаково
/// в индексе и в запросе, поиск лишь перестаёт их различать.
typealias SearchChar = UInt16
typealias SearchToken = UnsafeBufferPointer<SearchChar>

nonisolated struct TokenStore: Sendable {
    static func char(_ scalar: UInt32) -> SearchChar {
        scalar <= 0xFFFF ? SearchChar(scalar) : 0xFFFD
    }

    private var scalars: [SearchChar] = []
    /// Конец каждого слова в `scalars`.
    private var tokenEnds: [UInt32] = []
    /// Конец каждого ключа в `tokenEnds`.
    private var entryEnds: [UInt32] = []

    var count: Int { entryEnds.count }

    mutating func append(_ tokens: [SearchToken]) {
        for t in tokens {
            scalars.append(contentsOf: t)
            tokenEnds.append(UInt32(scalars.count))
        }
        entryEnds.append(UInt32(tokenEnds.count))
    }

    mutating func append<S: Sequence>(_ tokens: S) where S.Element: Collection<UInt32> {
        for t in tokens {
            scalars.append(contentsOf: t.map(Self.char))
            tokenEnds.append(UInt32(scalars.count))
        }
        entryEnds.append(UInt32(tokenEnds.count))
    }

    /// Как `append(SearchPreprocess.tokens(raw))`, но без временного массива на слово.
    mutating func appendTokenized(_ raw: String) {
        var inToken = false
        SearchPreprocess.forEachNormalizedScalar(raw) { c in
            if SearchPreprocess.isWordScalar(c) {
                scalars.append(Self.char(c))
                inToken = true
            } else if inToken {
                tokenEnds.append(UInt32(scalars.count))
                inToken = false
            }
        }
        if inToken { tokenEnds.append(UInt32(scalars.count)) }
        entryEnds.append(UInt32(tokenEnds.count))
    }

    /// Освобождает запас ёмкости после построения: `Array(array)` делит буфер,
    /// копия через указатель — нет.
    mutating func shrink() {
        scalars = scalars.withUnsafeBufferPointer(Array.init)
        tokenEnds = tokenEnds.withUnsafeBufferPointer(Array.init)
        entryEnds = entryEnds.withUnsafeBufferPointer(Array.init)
    }

    subscript(i: Int) -> [[UInt32]] {
        withView { view in
            var out: [SearchToken] = []
            view.appendTokens(of: i, to: &out)
            return out.map { $0.map(UInt32.init) }
        }
    }

    func withView<R>(_ body: (View) throws -> R) rethrows -> R {
        try scalars.withUnsafeBufferPointer { s in
            try tokenEnds.withUnsafeBufferPointer { t in
                try entryEnds.withUnsafeBufferPointer { e in
                    try body(View(scalars: s, tokenEnds: t, entryEnds: e))
                }
            }
        }
    }

    /// Указатели живут только внутри `withView`. `@unchecked Sendable`: память
    /// во время скана только читается, а `concurrentPerform` требует Sendable.
    struct View: @unchecked Sendable {
        let scalars: UnsafeBufferPointer<SearchChar>
        let tokenEnds: UnsafeBufferPointer<UInt32>
        let entryEnds: UnsafeBufferPointer<UInt32>

        func appendTokens(of i: Int, to out: inout [SearchToken]) {
            // В Release индексы UnsafeBufferPointer не проверяются — ошибка дала бы чтение мусора.
            precondition(i >= 0 && i < entryEnds.count)
            let first = i == 0 ? 0 : Int(entryEnds[i - 1])
            for t in first..<Int(entryEnds[i]) {
                let start = t == 0 ? 0 : Int(tokenEnds[t - 1])
                out.append(UnsafeBufferPointer(rebasing: scalars[start..<Int(tokenEnds[t])]))
            }
        }
    }
}
