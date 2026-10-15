/// Книги сущности по языкам: три плоских массива вместо словаря на каждого из 171k авторов.
nonisolated struct LanguageCounts: Sendable {
    /// По номеру сущности — конец её пар в `languages`/`counts`.
    private let ends: [UInt32]
    private let languages: [UInt16]
    private let counts: [UInt32]

    /// `keys` — по одному на книгу: номер сущности << 16 | номер языка.
    init(entityCount: Int, keys: [UInt64]) {
        let sorted = keys.sorted()
        var ends = [UInt32](repeating: 0, count: entityCount)
        var languages: [UInt16] = [], counts: [UInt32] = []
        var i = 0
        while i < sorted.count {
            var j = i + 1
            while j < sorted.count && sorted[j] == sorted[i] { j += 1 }
            languages.append(UInt16(truncatingIfNeeded: sorted[i]))
            counts.append(UInt32(j - i))
            ends[Int(sorted[i] >> 16)] = UInt32(languages.count)
            i = j
        }
        var last: UInt32 = 0
        for e in 0..<entityCount {
            if ends[e] == 0 { ends[e] = last } else { last = ends[e] }
        }
        self.ends = ends
        self.languages = languages
        self.counts = counts
    }

    func count(entity: Int, language: UInt16) -> Int {
        let start = entity == 0 ? 0 : Int(ends[entity - 1])
        for k in start..<Int(ends[entity]) where languages[k] == language {
            return Int(counts[k])
        }
        return 0
    }
}
