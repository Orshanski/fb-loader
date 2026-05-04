import Foundation

/// Normalises a string and splits it into a sequence of `[UInt32]` codepoint
/// tokens for fuzzy-matching consumption by `FuzzyScorer`.
///
/// Steps (applied in order):
/// 1. ё/Ё → е/Е (rapidfuzz default_process не делает этого; librarium делает,
///    потому что русские читатели часто пишут «е» вместо «ё»).
/// 2. Lowercase для ASCII A..Z и кириллицы А..Я (по диапазонам, без
///    `String.lowercased()` — избегаем grapheme-cluster overhead в горячем
///    цикле).
/// 3. Любой не-буквенный/не-цифровой codepoint — разделитель токенов.
///    Буквенность проверяем через `Unicode.Scalar.properties.isAlphabetic` —
///    это покрывает украинскую кириллицу (і, ї, є, ґ), белорусскую (ў),
///    латиницу с диакритикой (é, ü, ł) и пр. Без этого port-плана срезал бы
///    легитимные буквы во многих именах (см. ревью C2).
///
/// Возвращает массив непустых токенов, каждый — массив raw scalar.value
/// (UInt32). Скорер дальше работает на UInt32 и не возвращается в `String`.
///
/// `nonisolated` обязательно: проект собирается с
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, и без этой пометки функция
/// окажется MainActor-isolated, что сломает её вызов из `Task.detached`
/// внутри `SearchCoordinator` и из `DispatchQueue.concurrentPerform`.
@inline(__always)
nonisolated func isAlnumScalar(_ s: UInt32) -> Bool {
    if s >= 0x30 && s <= 0x39 { return true }       // ASCII digits 0..9
    guard let scalar = Unicode.Scalar(s) else { return false }
    return scalar.properties.isAlphabetic
}

nonisolated func preprocessTokens(_ raw: String) -> [[UInt32]] {
    if raw.isEmpty { return [] }
    var tokens: [[UInt32]] = []
    var current: [UInt32] = []
    current.reserveCapacity(16)
    for u in raw.unicodeScalars {
        var c = u.value
        // ё/Ё → е/Е
        if c == 0x0451 { c = 0x0435 }
        else if c == 0x0401 { c = 0x0435 }
        // ASCII upper → lower
        if c >= 0x41 && c <= 0x5A { c += 0x20 }
        // Cyrillic upper А..Я → а..я
        else if c >= 0x0410 && c <= 0x042F { c += 0x20 }
        if isAlnumScalar(c) {
            current.append(c)
        } else if !current.isEmpty {
            tokens.append(current)
            current = []
            current.reserveCapacity(16)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}
