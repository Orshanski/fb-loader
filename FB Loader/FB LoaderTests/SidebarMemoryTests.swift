import Testing
import Foundation
@testable import FB_Loader

@Suite("SidebarMemory")
struct SidebarMemoryTests {
    @Test("результат фильтра возвращается только при том же ключе фильтра")
    func itemsByFilterKey() {
        let m = SidebarMemory()
        m.store([1, 2, 3], filterKey: "ru|", for: "authors")
        #expect(m.items(Int.self, filterKey: "ru|", for: "authors") == [1, 2, 3])
        #expect(m.items(Int.self, filterKey: "en|", for: "authors") == nil)
        #expect(m.items(Int.self, filterKey: "ru|", for: "series") == nil)
    }

    @Test("прокрутка хранится по разделам и только для своего ключа фильтра")
    func scroll() {
        let m = SidebarMemory()
        m.setScroll(120, filterKey: "ru|", for: "authors")
        #expect(m.scroll(filterKey: "ru|", for: "authors") == 120)
        #expect(m.scroll(filterKey: "ru|аб", for: "authors") == nil)
        #expect(m.scroll(filterKey: "ru|", for: "series") == nil)
    }
}
