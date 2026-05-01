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
}
