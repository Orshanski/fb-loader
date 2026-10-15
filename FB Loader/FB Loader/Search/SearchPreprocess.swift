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

    /// Меняет ли NFC строку: комбинирующие знаки, гласные/финали хангыля или
    /// символы, которые NFC заменяет даже в одиночку (синглтоны и исключения
    /// композиции) — иначе их форма зависела бы от остальной строки.
    nonisolated static func needsComposition(_ raw: String) -> Bool {
        for u in raw.unicodeScalars {
            let v = u.value
            // Здесь NFC не меняет ничего, кроме перечисленных синглтонов.
            if v < 0x0300 || (v >= 0x048A && v < 0x0591) { continue }
            if v >= 0x0370 && v < 0x0483 {
                if v == 0x0374 || v == 0x037E || v == 0x0387 { return true }
                continue
            }
            if isNFCSingleton(v) { return true }
            switch u.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: return true
            default: continue
            }
        }
        return false
    }

    /// Синглтоны и исключения композиции вне знаков (по CompositionExclusions.txt
    /// и DerivedNormalizationProps NFC_QC=No); сверено перебором всех скаляров.
    private nonisolated static func isNFCSingleton(_ v: UInt32) -> Bool {
        switch v {
        case 0x0958...0x095F, 0x09DC, 0x09DD, 0x09DF, 0x0A33, 0x0A36, 0x0A59...0x0A5B, 0x0A5E,
             0x0B5C, 0x0B5D, 0x0F43, 0x0F4D, 0x0F52, 0x0F57, 0x0F5C, 0x0F69, 0x0F73, 0x0F75, 0x0F81,
             0x1160...0x11FF, 0x1F70...0x1FFF, 0x2000, 0x2001, 0x2126, 0x212A, 0x212B, 0x2329, 0x232A,
             0x2ADC, 0xF900...0xFAFF, 0xFB1D...0xFB4E, 0x1D15E...0x1D164, 0x1D1BB...0x1D1C0,
             0x2F800...0x2FA1F:
            return true
        default:
            return false
        }
    }

    nonisolated static func normalized(_ scalar: UInt32) -> UInt32 {
        let c = scalar
        if c < 0x80 { return c >= 0x41 && c <= 0x5A ? c + 0x20 : c }
        if c == 0x0451 || c == 0x0401 { return 0x0435 }
        if c >= 0x0430 && c <= 0x045F { return c }
        if c >= 0x0410 && c <= 0x042F { return c + 0x20 }
        if c >= 0x0400 && c <= 0x040F { return c + 0x50 }
        // Конечная ς — та же буква σ, как ё для е.
        if c == 0x03C2 { return 0x03C3 }
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
