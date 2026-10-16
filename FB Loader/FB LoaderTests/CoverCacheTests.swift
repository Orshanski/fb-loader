import Testing
import Foundation
@testable import FB_Loader

@Suite("CoverCache")
struct CoverCacheTests {
    private func book(_ libid: Int32) -> Book {
        Book(libid: libid, title: "B", authorIDs: [1], seriesID: nil, seriesNum: nil,
             genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAdded: nil)
    }

    private func withCache(limit: Int, _ body: (CoverCache, URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("covercache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(try CoverCache(directory: dir, limitBytes: limit), dir)
    }

    private func age(_ dir: URL, libid: Int32, secondsAgo: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -secondsAgo)],
            ofItemAtPath: dir.appendingPathComponent("\(libid).jpg").path)
    }

    private func names(_ dir: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
    }

    @Test("в пределах лимита ничего не удаляется")
    func underLimit() throws {
        try withCache(limit: 1000) { cache, dir in
            _ = cache.store(Data(count: 100), for: book(1))
            _ = cache.store(Data(count: 100), for: book(2))
            let n = try names(dir)
            #expect(n == ["1.jpg", "2.jpg"])
        }
    }

    @Test("при превышении удаляются самые старые, свежая запись остаётся, размер ниже лимита")
    func evictsOldest() throws {
        try withCache(limit: 1000) { cache, dir in
            for id in 1...4 {
                try Data(count: 250).write(to: dir.appendingPathComponent("\(id).jpg"))
            }
            try age(dir, libid: 1, secondsAgo: 400)
            try age(dir, libid: 2, secondsAgo: 300)
            try age(dir, libid: 3, secondsAgo: 200)
            try age(dir, libid: 4, secondsAgo: 100)
            _ = cache.store(Data(count: 250), for: book(5))
            let left = try names(dir)
            #expect(left.contains("5.jpg"))
            #expect(!left.contains("1.jpg") && !left.contains("2.jpg"))
            let total = try left.reduce(0) {
                $0 + (try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent($1).path)[.size] as! Int)
            }
            #expect(total <= 1000)
        }
    }

    @Test("записанная только что книга остаётся, даже если она одна больше лимита")
    func keepsFresh() throws {
        try withCache(limit: 100) { cache, dir in
            _ = cache.store(Data(count: 500), for: book(1))
            let n = try names(dir)
            #expect(n == ["1.jpg"])
        }
    }

    @Test("попадание в кэш обновляет возраст: недавно прочитанная обложка переживает вытеснение")
    func hitRefreshesAge() throws {
        try withCache(limit: 600) { cache, dir in
            _ = cache.store(Data(count: 200), for: book(1))
            _ = cache.store(Data(count: 200), for: book(2))
            try age(dir, libid: 1, secondsAgo: 500)
            try age(dir, libid: 2, secondsAgo: 400)
            _ = cache.cachedImage(for: book(1))
            _ = cache.store(Data(count: 300), for: book(3))
            let left = try names(dir)
            #expect(left.contains("1.jpg") && left.contains("3.jpg"))
            #expect(!left.contains("2.jpg"))
        }
    }
}
