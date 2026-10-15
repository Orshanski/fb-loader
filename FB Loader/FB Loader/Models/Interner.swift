/// Одинаковым массивам — один буфер. У книг одного автора одинаковые
/// `authorIDs`, а различных наборов жанров — тысячи на 594k книг.
nonisolated struct Interner<Element: Hashable> {
    private var seen: Set<[Element]> = []

    mutating func intern(_ array: [Element]) -> [Element] {
        seen.insert(array).memberAfterInsert
    }
}
