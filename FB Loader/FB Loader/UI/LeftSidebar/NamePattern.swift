import Foundation

/// Filter query for sidebar lists (authors, series).
///
/// Two modes, chosen by whether the raw query contains `*`:
///
/// 1. Plain word — no `*`. Matches when any word inside the candidate name
///    starts with the query. "Олди" matches "Олди" and "Олдисс" but NOT
///    "Болдин", because in "болдин" no word boundary precedes "олди".
///    Word boundaries are the start of the string or any non-letter,
///    non-digit character.
///
/// 2. Glob — at least one `*`. Segments split by `*` must occur in order.
///    A leading `*` un-anchors the start, a trailing `*` un-anchors the end:
///    `пет*` = prefix, `*пет` = suffix, `*пет*` = substring,
///    `пет*ров` = starts with "пет" and ends with "ров".
///
/// Inputs are matched against pre-lowercased candidate names; the pattern
/// itself is lowercased once at construction time. Empty / whitespace-only
/// queries collapse to `.all`.
enum NamePattern: Sendable, Equatable {
    case all
    case wordPrefix(String)
    case glob(segments: [String], anchorStart: Bool, anchorEnd: Bool)

    init(query raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty { self = .all; return }
        if trimmed.contains("*") {
            let parts = trimmed.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
            let anchorStart = !(parts.first?.isEmpty ?? true)
            let anchorEnd = !(parts.last?.isEmpty ?? true)
            let segments = parts.filter { !$0.isEmpty }
            if segments.isEmpty { self = .all; return }
            self = .glob(segments: segments, anchorStart: anchorStart, anchorEnd: anchorEnd)
            return
        }
        self = .wordPrefix(trimmed)
    }

    /// Caller MUST pass a name that is already lowercased — the sidebar
    /// pre-computes these (`Library.lowercasedAuthorNames` etc.) to avoid
    /// re-allocating on every keystroke across 100k+ candidates.
    func matches(_ lowercasedName: String) -> Bool {
        switch self {
        case .all:
            return true
        case .wordPrefix(let prefix):
            return Self.containsWordPrefix(lowercasedName, prefix: prefix)
        case .glob(let segments, let anchorStart, let anchorEnd):
            return Self.matchGlob(lowercasedName, segments: segments,
                                  anchorStart: anchorStart, anchorEnd: anchorEnd)
        }
    }

    static func containsWordPrefix(_ name: String, prefix: String) -> Bool {
        if prefix.isEmpty { return true }
        if name.hasPrefix(prefix) { return true }
        var searchStart = name.startIndex
        while searchStart < name.endIndex,
              let r = name.range(of: prefix, range: searchStart..<name.endIndex) {
            // r.lowerBound > startIndex because hasPrefix above already
            // covered the start-of-string case.
            let prev = name.index(before: r.lowerBound)
            let prevChar = name[prev]
            if !prevChar.isLetter && !prevChar.isNumber { return true }
            searchStart = name.index(after: r.lowerBound)
        }
        return false
    }

    static func matchGlob(_ name: String, segments: [String],
                          anchorStart: Bool, anchorEnd: Bool) -> Bool {
        guard !segments.isEmpty else { return true }
        var cursor = name.startIndex
        let lastIdx = segments.count - 1
        for (idx, seg) in segments.enumerated() {
            let isFirst = (idx == 0)
            let isLast = (idx == lastIdx)
            if isFirst && anchorStart {
                guard name[cursor...].hasPrefix(seg) else { return false }
                cursor = name.index(cursor, offsetBy: seg.count)
            } else if isLast && anchorEnd {
                guard let r = name.range(of: seg, options: .backwards,
                                         range: cursor..<name.endIndex),
                      r.upperBound == name.endIndex else { return false }
                cursor = r.upperBound
            } else {
                guard let r = name.range(of: seg, range: cursor..<name.endIndex) else { return false }
                cursor = r.upperBound
            }
        }
        return true
    }
}
