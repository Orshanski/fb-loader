import Testing
import Foundation
@testable import FB_Loader

@Suite("SidebarMemory")
struct SidebarMemoryTests {
    private func library() -> Library {
        Library(inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
                authors: [], series: [], genres: [], books: [])
    }

    @Test("результат фильтра возвращается только при том же ключе фильтра")
    func itemsByFilterKey() {
        let m = SidebarMemory()
        m.bind(library())
        m.store([1, 2, 3], filterKey: "ru|", for: "authors")
        #expect(m.items(Int.self, filterKey: "ru|", for: "authors") == [1, 2, 3])
        #expect(m.items(Int.self, filterKey: "en|", for: "authors") == nil)
        #expect(m.items(Int.self, filterKey: "ru|", for: "series") == nil)
    }

    @Test("прокрутка хранится по разделам")
    func scroll() {
        let m = SidebarMemory()
        m.bind(library())
        m.setScroll(120, for: "authors")
        #expect(m.scroll(for: "authors") == 120)
        #expect(m.scroll(for: "series") == nil)
    }

    @Test("другая библиотека сбрасывает память, та же — нет")
    func rebind() {
        let m = SidebarMemory()
        let lib = library()
        m.bind(lib)
        m.store([1], filterKey: "k", for: "authors")
        m.setScroll(5, for: "authors")
        m.bind(lib)
        #expect(m.items(Int.self, filterKey: "k", for: "authors") == [1])
        m.bind(library())
        #expect(m.items(Int.self, filterKey: "k", for: "authors") == nil)
        #expect(m.scroll(for: "authors") == nil)
    }
}
