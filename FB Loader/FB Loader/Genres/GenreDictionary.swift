import Foundation

/// Loads and queries the FB2 genre dictionary embedded in the app bundle.
/// Source: extracted from freeLib.sqlite `genre` table.
final class GenreDictionary {
    private struct RawEntry: Decodable {
        let id: Int16
        let name: String
        let parent_id: Int16
        let keys: String?
    }

    let allGenres: [Genre]
    private let byCode: [String: Genre]
    /// Synthetic genres created on demand for unknown FB2 codes.
    /// Negative IDs to avoid collision with real ones.
    private var syntheticByCode: [String: Genre] = [:]
    private var nextSyntheticID: Int16 = -1

    private init(rawEntries: [RawEntry]) {
        var all: [Genre] = []
        var byCode: [String: Genre] = [:]
        for r in rawEntries {
            let parent: Int16? = r.parent_id == 0 ? nil : r.parent_id
            // The "keys" column holds FB2 codes separated by ';' (matches freeLib
            // importthread.cpp:609). Names in freeLib.sqlite have trailing whitespace
            // (252/322 rows), so trim.
            let name = r.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let keys = (r.keys ?? "")
                .split(separator: ";", omittingEmptySubsequences: true)
                .map(String.init)
            for code in keys {
                let g = Genre(id: r.id, code: code, name: name, parentID: parent)
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
        return GenreDictionary(rawEntries: raw)
    }

    /// Returns a genre for the given FB2 code. For unknown codes, synthesizes
    /// a `Genre` whose `name` equals the code itself (per spec §7).
    func genre(forCode code: String) -> Genre? {
        if let g = byCode[code] { return g }
        if let g = syntheticByCode[code] { return g }
        let g = Genre(id: nextSyntheticID, code: code, name: code, parentID: nil)
        nextSyntheticID -= 1
        syntheticByCode[code] = g
        return g
    }
}
