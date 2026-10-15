import Foundation

/// Какой из сохранённых путей нужно спросить у пользователя при запуске.
nonisolated enum MissingPaths: Equatable, Sendable {
    /// Ни одного пути — INPX, папка архивов по умолчанию рядом с ним.
    case both
    case inpx
    case archives

    /// `nil` — оба пути на месте.
    static func check(inpx: URL?, archives: URL?, isReachable: (URL) -> Bool) -> MissingPaths? {
        let inpxOK = inpx.map(isReachable) ?? false
        let archivesOK = archives.map(isReachable) ?? false
        switch (inpxOK, archivesOK) {
        case (true, true): return nil
        case (true, false): return .archives
        case (false, true): return .inpx
        case (false, false): return .both
        }
    }

    /// Пара путей после выбора `picked`; второй путь берётся сохранённый.
    func resolve(picked: URL, inpx: URL?, archives: URL?) -> (inpx: URL, archives: URL)? {
        switch self {
        case .both:
            return (picked, picked.deletingLastPathComponent())
        case .inpx:
            guard let archives else { return nil }
            return (picked, archives)
        case .archives:
            guard let inpx else { return nil }
            return (inpx, picked)
        }
    }
}
