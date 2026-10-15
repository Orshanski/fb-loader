import Testing
import Foundation
@testable import FB_Loader

@Suite("GenreDictionary")
struct GenreDictionaryTests {
    @Test("loads all entries from bundle")
    func loadsBundle() throws {
        let dict = try GenreDictionary.loadFromBundle()
        #expect(dict.allGenres.count > 200)
    }

    @Test("resolves a known FB2 code to its exact Russian name")
    func resolvesKnownCode() throws {
        // Snapshot test against the committed genres.json — intentionally brittle:
        // if the dump is re-exported and id/name change, this test breaks on purpose.
        let dict = try GenreDictionary.loadFromBundle()
        let g = dict.genre(forCode: "sf_social")
        #expect(g?.name == "Социальная фантастика")
        #expect(g?.id == 106)
    }

    @Test("multi-code entry: every code resolves to the same genre id and name")
    func multiCodeEntry() throws {
        // genres.json id=207 has keys "prose;prose_all;" — both must resolve identically.
        let dict = try GenreDictionary.loadFromBundle()
        let prose = dict.genre(forCode: "prose")
        let proseAll = dict.genre(forCode: "prose_all")
        #expect(prose?.id == 207)
        #expect(proseAll?.id == 207)
        #expect(prose?.name == proseAll?.name)
    }

    @Test("synthesizes a Genre with code as name for unknown codes")
    func unknownCode() throws {
        let dict = try GenreDictionary.loadFromBundle()
        let g = dict.genre(forCode: "made_up_genre_xyz")
        #expect(g?.name == "made_up_genre_xyz")
        #expect(g?.code == "made_up_genre_xyz")
    }

    @Test("synthetic genres are cached: repeated calls return the same id")
    func syntheticIsStable() throws {
        let dict = try GenreDictionary.loadFromBundle()
        let first = dict.genre(forCode: "made_up_genre_xyz")
        let second = dict.genre(forCode: "made_up_genre_xyz")
        #expect(first?.id == second?.id)
    }

    @Test("empty code returns nil instead of synthesizing a junk genre")
    func emptyCodeReturnsNil() throws {
        let dict = try GenreDictionary.loadFromBundle()
        #expect(dict.genre(forCode: "") == nil)
    }

    @Test("жанры Флибусты, которых не было у freeLib, — с русским названием и разделом",
          arguments: [("fan_translation", "Любительский перевод", Int16(11)),
                      ("boyar_anime", "Бояръ-аниме", Int16(1)),
                      ("child_tale_russian_writers", "Сказки отечественных писателей", Int16(7)),
                      ("det_lady", "Дамский детективный роман", Int16(4)),
                      ("nonf_biography_writers", "Биографии и мемуары: писатели, поэты, драматурги", Int16(5)),
                      ("sci_psychology_popular", "Популярная психология", Int16(3))])
    func flibustaGenres(code: String, name: String, parent: Int16) throws {
        let g = try #require(try GenreDictionary.loadFromBundle().genre(forCode: code))
        #expect(g.id > 0)
        #expect(g.name == name)
        #expect(g.parentID == parent)
    }

    @Test("название вместо кода находит жанр словаря", arguments: [
        ("Биографии и мемуары", Int16(500)), ("Шпионский Детектив", Int16(410))])
    func nameInsteadOfCode(raw: String, id: Int16) throws {
        #expect(try GenreDictionary.loadFromBundle().genre(forCode: raw)?.id == id)
    }

    @Test("незнакомый код — в разделе «Прочее», а не корневым разделом")
    func syntheticUnderOther() throws {
        let g = try #require(try GenreDictionary.loadFromBundle().genre(forCode: "made_up_genre_xyz"))
        #expect(g.parentID == GenreDictionary.otherSectionID)
    }

    @Test("раздел «Прочее» есть в словаре и он корневой")
    func otherSectionExists() throws {
        let other = try GenreDictionary.loadFromBundle().allGenres
            .first { $0.id == GenreDictionary.otherSectionID }
        #expect(other?.name == "Прочее")
        #expect(other?.parentID == nil)
    }

    @Test("целостность словаря: уникальные id, существующие родители")
    func integrity() throws {
        let all = try GenreDictionary.loadFromBundle().allGenres
        let ids = Set(all.map(\.id))
        #expect(ids.count == all.count)
        #expect(all.compactMap(\.parentID).allSatisfy(ids.contains))
    }

    @Test("коды не повторяются, кроме четырёх известных дублей freeLib")
    func keyCollisions() throws {
        let url = try #require(Bundle.main.url(forResource: "genres", withExtension: "json"))
        struct Raw: Decodable { let keys: String? }
        let raw = try JSONDecoder().decode([Raw].self, from: Data(contentsOf: url))
        var seen: [String: Int] = [:]
        for r in raw { for k in (r.keys ?? "").split(separator: ";") { seen[String(k), default: 0] += 1 } }
        let dups = Set(seen.filter { $0.value > 1 }.keys)
        #expect(dups == ["adv_animal", "adv_geo", "child_adv", "drama_antique"])
    }

    @Test("жанры для каталога включают синтетические")
    func libraryGenresIncludeSynthetic() throws {
        let dict = try GenreDictionary.loadFromBundle()
        let g = try #require(dict.genre(forCode: "made_up_genre_xyz"))
        #expect(dict.libraryGenres.contains(g))
        #expect(dict.libraryGenres.count == dict.allGenres.count + 1)
    }

    @Test("синтетические id кончились — nil, а не падение")
    func syntheticIDsExhausted() throws {
        let dict = try GenreDictionary.loadFromBundle()
        let made = (0..<32_768).filter { dict.genre(forCode: "u\($0)") != nil }.count
        #expect(made == 32_768)
        #expect(dict.genre(forCode: "one_too_many") == nil)
        #expect(dict.genre(forCode: "u0") != nil)
    }

    @Test("отпечаток genres.json — 32 байта и стабилен")
    func fingerprint() throws {
        let a = try GenreDictionary.loadFromBundle()
        let b = try GenreDictionary.loadFromBundle()
        #expect(a.fingerprint.count == 32)
        #expect(a.fingerprint == b.fingerprint)
    }
}
