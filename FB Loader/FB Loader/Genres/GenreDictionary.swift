import Foundation

/// Source: freeLib.sqlite `genre` table plus Flibusta genres freeLib lacks (flibusta.is/g, 2026-10-15).
///
/// Not Sendable: `genre(forCode:)` mutates synthetic-genre caches, so use one instance per isolation
/// domain. `INPXImporter` discards it after parsing; only resolved `Genre` values reach `Library`.
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

    /// Раздел «Прочее»: синтетические жанры кладутся сюда, а не корневыми разделами.
    static let otherSectionID: Int16 = 11

    let allGenres: [Genre]
    let fingerprint: Data
    private let byCode: [String: Genre]
    /// Synthetic genres for unknown FB2 codes; negative IDs cannot collide with real ones.
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
                // Last entry wins, as in freeLib's QHash insertion (importthread.cpp:613). Of the 4 duplicated
                // codes only `child_adv` truly conflicts; it resolves to id=1012.
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

    /// Unknown non-empty codes get a cached synthetic `Genre` named after the code; `nil` for the empty string.
    func genre(forCode code: String) -> Genre? {
        guard !code.isEmpty else { return nil }
        if let g = byCode[code] { return g }
        // В части INPX вместо кода — название; у freeLib для них ключи вида «биографии_и_мемуары».
        if let g = byCode[code.lowercased().replacingOccurrences(of: " ", with: "_")] { return g }
        if let g = syntheticByCode[code] { return g }
        guard let id = nextSyntheticID else { return nil }
        let g = Genre(id: id, code: code, name: code, parentID: Self.otherSectionID)
        nextSyntheticID = id == Int16.min ? nil : id - 1
        syntheticByCode[code] = g
        return g
    }
}
