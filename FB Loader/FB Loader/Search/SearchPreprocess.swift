import Foundation

/// Search-text normalization for the fuzzy scorer pipeline.
///
/// `tokens(_:)` normalises a string and splits it into a sequence of
/// `[UInt32]` codepoint tokens, ready to feed into `FuzzyScorer`.
///
/// Steps (applied in order):
/// 1. ё/Ё → е (rapidfuzz's `default_process` doesn't do this; librarium does
///    because Russian readers commonly type «е» where the literal text has «ё»).
/// 2. Lowercase для ASCII A..Z и кириллицы А..Я (по диапазонам, без
///    `String.lowercased()` — избегаем grapheme-cluster overhead в горячем
///    цикле).
///    NB: украинские/белорусские буквы и латиница с диакритикой остаются в
///    исходном регистре. Это безопасно — preprocess применяется одинаково
///    к запросу и к индексу, так что верхнерегистровый Ї совпадёт с
///    верхнерегистровым Ї. Однако смешанный регистр в исходных данных
///    (Київ vs КИЇВ) даст две разные канонические формы. Если такой
///    сценарий появится, переходим на `String.lowercased()` + bench.
/// 3. Любой не-буквенный/не-цифровой codepoint — разделитель токенов.
///    Буквенность проверяем через `Unicode.Scalar.properties.isAlphabetic` —
///    это покрывает украинскую кириллицу (і, ї, є, ґ), белорусскую (ў),
///    латиницу с диакритикой (é, ü, ł) и пр. Без этого порт срезал бы
///    легитимные буквы во многих именах (см. ревью C2).
///
/// Возвращает массив непустых токенов, каждый — массив raw scalar.value
/// (UInt32). Скорер дальше работает на UInt32 и не возвращается в `String`.
///
/// `nonisolated` обязательно: проект собирается с
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, и без этой пометки функция
/// окажется MainActor-isolated, что сломает её вызов из `Task.detached`
/// внутри `SearchCoordinator` и из `DispatchQueue.concurrentPerform`.
nonisolated enum SearchPreprocess {
    nonisolated static func tokens(_ raw: String) -> [[UInt32]] {
        if raw.isEmpty { return [] }
        var tokens: [[UInt32]] = []
        var current: [UInt32] = []
        // 16 — эмпирический size-hint под средне-длинное слово в каталоге
        // (имена авторов, названия). Конкретное число не критично — ARC/CoW
        // всё равно перевыделит при росте, — но стартовая ёмкость избегает
        // первых 4→8→16 пере-аллокаций для типичного входа.
        current.reserveCapacity(16)
        for u in raw.unicodeScalars {
            let c = normalized(u.value)
            if isWordScalar(c) {
                current.append(c)
            } else if !current.isEmpty {
                // CoW: tokens.append(current) копирует ссылку на буфер;
                // перевыделение через `current = []` + reserveCapacity
                // — это явный fresh-buffer pattern, чтобы следующая
                // мутация не CoW-копировала уже сохранённый в tokens
                // буфер.
                tokens.append(current)
                current = []
                current.reserveCapacity(16)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    nonisolated static func normalized(_ scalar: UInt32) -> UInt32 {
        var c = scalar
        // ё (U+0451) и Ё (U+0401) → е (U+0435). Ё лежит вне диапазона
        // А..Я (U+0410..U+042F), поэтому lowercase-блок ниже её
        // не двигает повторно.
        if c == 0x0451 || c == 0x0401 { c = 0x0435 }
        // ASCII upper → lower
        if c >= 0x41 && c <= 0x5A { c += 0x20 }
        // Cyrillic upper А..Я → а..я
        else if c >= 0x0410 && c <= 0x042F { c += 0x20 }
        return c
    }

    /// True if `s` is an ASCII digit OR any Unicode-alphabetic scalar
    /// (letters from any script, including marks-with-letter-semantics
    /// per UAX #29). Drives the token-boundary decision in `tokens(_:)`.
    nonisolated static func isWordScalar(_ s: UInt32) -> Bool {
        if s >= 0x30 && s <= 0x39 { return true }       // ASCII digits 0..9
        guard let scalar = Unicode.Scalar(s) else { return false }
        return scalar.properties.isAlphabetic
    }
}
