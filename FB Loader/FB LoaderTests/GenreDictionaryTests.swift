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

    @Test("resolves a known FB2 code (sf_social) to a Russian name")
    func resolvesKnownCode() throws {
        let dict = try GenreDictionary.loadFromBundle()
        let g = dict.genre(forCode: "sf_social")
        #expect(g != nil)
        #expect(g?.name.contains("оциал") ?? false || (g?.name.contains("ант") ?? false))
    }

    @Test("returns synthetic genre with code as name for unknown codes")
    func unknownCode() throws {
        let dict = try GenreDictionary.loadFromBundle()
        let g = dict.genre(forCode: "made_up_genre_xyz")
        #expect(g?.name == "made_up_genre_xyz")
    }
}
