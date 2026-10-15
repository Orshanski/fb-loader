import Foundation

/// Loads and queries the FB2 genre dictionary embedded in the app bundle.
/// Source: extracted from freeLib.sqlite `genre` table.
///
/// **Concurrency:** not Sendable. `genre(forCode:)` mutates internal caches
/// (`syntheticByCode`, `nextSyntheticID`) when synthesizing entries for unknown
/// codes. Callers must access a single instance from one isolation domain.
/// In FB Loader, `INPXImporter` uses it during INPX parse and then discards it —
/// only the resolved `Genre` values flow into the `Sendable` `Library` snapshot.
nonisolated final class GenreDictionary {
    private struct RawEntry: Decodable {
        let id: Int16
        let name: String
        let parentID: Int16
        let keys: String?

        // Explicit mapping so `parentID` (camelCase, matches Genre.parentID)
        // decodes from JSON key `"parent_id"` regardless of any global
        // `keyDecodingStrategy` the loader might add later.
        private enum CodingKeys: String, CodingKey {
            case id, name, keys
            case parentID = "parent_id"
        }
    }

    let allGenres: [Genre]
    let fingerprint: Data
    private let byCode: [String: Genre]
    /// Synthetic genres created on demand for unknown FB2 codes.
    /// Negative IDs to avoid collision with real ones.
    private var syntheticByCode: [String: Genre] = [:]
    private var nextSyntheticID: Int16? = -1

    var libraryGenres: [Genre] {
        allGenres + syntheticByCode.values.sorted { $0.id > $1.id }
    }

    private init(rawEntries: [RawEntry], fingerprint: Data) {
        self.fingerprint = fingerprint
        var all: [Genre] = []
        var byCode: [String: Genre] = [:]
        for r in rawEntries {
            let parent: Int16? = r.parentID == 0 ? nil : r.parentID
            // The "keys" column holds FB2 codes separated by ';' (matches freeLib
            // importthread.cpp:609). Names in freeLib.sqlite have trailing whitespace
            // (252/322 rows), so trim.
            let name = r.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let keys = (r.keys ?? "")
                .split(separator: ";", omittingEmptySubsequences: true)
                .map(String.init)
            for code in keys {
                let g = Genre(id: r.id, code: code, name: name, parentID: parent)
                // Last entry wins on collisions. Source data has 4 codes that
                // appear twice (adv_animal, adv_geo, child_adv, drama_antique);
                // three are same-name duplicates from twin subtrees. `child_adv`
                // is the only true conflict — it always resolves to id=1012
                // ("Приключения для детей и подростков"). Matches freeLib's
                // QHash insertion semantics in importthread.cpp:613.
                byCode[code] = g
            }
            // Also keep one entry per `id` for navigation. Top-level categories
            // have empty `keys`, so `code` is "" — they're only reachable via parentID.
            all.append(Genre(id: r.id, code: keys.first ?? "", name: name, parentID: parent))
        }
        self.allGenres = all
        self.byCode = byCode
    }

    static func loadFromBundle(bundle: Bundle = .main) throws -> GenreDictionary {
        guard let url = bundle.url(forResource: "genres", withExtension: "json") else {
            throw NSError(domain: "GenreDictionary", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "genres.json not found in bundle"])
        }
        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode([RawEntry].self, from: data)
        return GenreDictionary(rawEntries: raw, fingerprint: SHA256.hash(of: data))
    }

    /// Returns a genre for the given FB2 code. For unknown non-empty codes,
    /// synthesizes a `Genre` whose `name` equals the code itself (per spec §7)
    /// and caches it so repeated lookups are stable. Returns `nil` for the
    /// empty string — there are no "" keys in the source dictionary, and a
    /// synthetic genre with empty code/name is never useful.
    func genre(forCode code: String) -> Genre? {
        guard !code.isEmpty else { return nil }
        if let g = byCode[code] { return g }
        if let g = syntheticByCode[code] { return g }
        guard let id = nextSyntheticID else { return nil }
        let g = Genre(id: id, code: code, name: code, parentID: nil)
        nextSyntheticID = id == Int16.min ? nil : id - 1
        syntheticByCode[code] = g
        return g
    }
}
