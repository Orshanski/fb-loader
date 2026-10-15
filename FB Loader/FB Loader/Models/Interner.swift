/// Одинаковым массивам — один буфер. У книг одного автора одинаковые
/// `authorIDs`, а различных наборов жанров — тысячи на 594k книг.
nonisolated struct Interner<Element: Hashable> {
    private var seen: Set<[Element]> = []

    mutating func intern(_ array: [Element]) -> [Element] {
        if let existing = seen.firstIndex(of: array) { return seen[existing] }
        seen.insert(array)
        return array
    }
}
