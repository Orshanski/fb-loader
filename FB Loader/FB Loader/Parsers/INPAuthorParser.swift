import Foundation

/// Parses INP `AUTHOR` field into structured triples.
/// Format: authors separated by `:`; each is `LastName,FirstName,MiddleName`.
/// All three components are optional (any may be empty).
nonisolated enum INPAuthorParser {
    /// `Hashable` so `INPXImporter` can dedup authors via a dictionary keyed by triple.
    struct Triple: Hashable {
        let lastName: String
        let firstName: String
        let middleName: String
    }

    static func parse(_ field: String) -> [Triple] {
        guard !field.isEmpty else { return [] }
        return field.split(separator: ":", omittingEmptySubsequences: true).map { part in
            let comps = part.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
            func at(_ i: Int) -> String {
                i < comps.count ? String(comps[i]).trimmingCharacters(in: .whitespaces) : ""
            }
            return Triple(lastName: at(0), firstName: at(1), middleName: at(2))
        }
    }

    /// Detects records that mean "no known author".
    /// Matches the heuristics in importthread.cpp:951-953.
    static func isUnknown(lastName: String, firstName: String, middleName: String) -> Bool {
        let joined = (lastName + " " + firstName + " " + middleName).lowercased()
        if joined.contains("автор") &&
           (joined.contains("неизвестен") || joined.contains("неизвестный")) {
            return true
        }
        if joined.trimmingCharacters(in: .whitespaces) == "неизвестно" { return true }
        return false
    }
}
