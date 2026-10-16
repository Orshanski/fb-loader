import Foundation

/// Filter query for sidebar lists, in two modes chosen by whether the raw query contains `*`:
/// - Plain word: any word of the name starts with the query. "Олди" matches "Олдисс" but not "Болдин";
///   word boundaries are the string start or any non-letter, non-digit character.
/// - Glob: segments split by `*` must occur in order; a leading/trailing `*` un-anchors that end
///   (`пет*` prefix, `*пет` suffix, `*пет*` substring, `пет*ров` anchored on both).
///
/// Candidates are pre-lowercased, the pattern is lowercased once. Blank queries collapse to `.all`.
nonisolated enum NamePattern: Sendable, Equatable {
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

    /// `lowercasedName` must already be lowercased (`Library.lowercasedAuthorNames` etc.): the sidebar
    /// precomputes them to avoid allocating on every keystroke.
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
