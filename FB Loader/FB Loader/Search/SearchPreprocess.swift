import Foundation

/// Search-text normalization for the fuzzy scorer pipeline.
///
/// `tokens(_:)` normalises a string and splits it into a sequence of
/// `[UInt32]` codepoint tokens, ready to feed into `FuzzyScorer`.
///
/// Steps (applied in order):
/// 0. NFC: разложенная «e + U+0301» склеивается в «é». Только для строк с
///    комбинирующими знаками — проверка дешевле безусловной нормализации.
/// 1. ё/Ё → е (rapidfuzz's `default_process` doesn't do this; librarium does
///    because Russian readers commonly type «е» where the literal text has «ё»).
/// 2. Lowercase любой письменности посимвольно; ASCII и кириллица — по
///    диапазонам, остальное — через Unicode-свойства (без `String.lowercased()`
///    и его аллокаций в горячем цикле).
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
        forEachNormalizedScalar(raw) { c in
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

    /// Единая точка входа для индекса и запроса: NFC (при необходимости) + `normalized`.
    @inline(__always)
    nonisolated static func forEachNormalizedScalar(_ raw: String, _ body: (UInt32) -> Void) {
        if needsComposition(raw) {
            for u in raw.precomposedStringWithCanonicalMapping.unicodeScalars { body(normalized(u.value)) }
        } else {
            for u in raw.unicodeScalars { body(normalized(u.value)) }
        }
    }

    /// Есть ли что склеивать NFC: комбинирующие знаки или гласные/финали хангыля.
    nonisolated static func needsComposition(_ raw: String) -> Bool {
        for u in raw.unicodeScalars {
            let v = u.value
            // До U+0300 и буквы греческого/кириллицы/армянского — знаков нет.
            if v < 0x0300 || (v >= 0x0370 && v < 0x0483) || (v >= 0x048A && v < 0x0591) { continue }
            if v >= 0x1160 && v <= 0x11FF { return true }
            switch u.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: return true
            default: continue
            }
        }
        return false
    }

    nonisolated static func normalized(_ scalar: UInt32) -> UInt32 {
        let c = scalar
        if c < 0x80 { return c >= 0x41 && c <= 0x5A ? c + 0x20 : c }
        // ё (U+0451) и Ё (U+0401) → е (U+0435).
        if c == 0x0451 || c == 0x0401 { return 0x0435 }
        if c >= 0x0430 && c <= 0x045F { return c }
        if c >= 0x0410 && c <= 0x042F { return c + 0x20 }
        if c >= 0x0400 && c <= 0x040F { return c + 0x50 }
        guard let u = Unicode.Scalar(c), u.properties.changesWhenLowercased else { return c }
        // Многосимвольная форма есть только у İ («i» + U+0307): берём «i», иначе
        // комбинирующая точка разорвала бы слово.
        return u.properties.lowercaseMapping.unicodeScalars.first?.value ?? c
    }

    /// True if `s` is an ASCII digit OR any Unicode-alphabetic scalar
    /// (letters from any script, including marks-with-letter-semantics
    /// per UAX #29). Drives the token-boundary decision in `tokens(_:)`.
    nonisolated static func isWordScalar(_ s: UInt32) -> Bool {
        if s < 0x80 { return (s >= 0x30 && s <= 0x39) || (s >= 0x61 && s <= 0x7A) || (s >= 0x41 && s <= 0x5A) }
        if s >= 0x0410 && s <= 0x044F { return true }
        guard let scalar = Unicode.Scalar(s) else { return false }
        return scalar.properties.isAlphabetic
    }
}
