import Testing
import Foundation
@testable import FB_Loader

private func storage<T>(_ a: [T]) -> UnsafeRawPointer? {
    a.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
}

@Suite("Interner")
struct InternerTests {
    @Test("одинаковые массивы получают общий буфер, разные — нет")
    func sharesStorage() {
        var interner = Interner<Int32>()
        let a = interner.intern([1, 2])
        let b = interner.intern([1, 2])
        let c = interner.intern([3])
        #expect(a == [1, 2] && b == [1, 2] && c == [3])
        #expect(storage(a) == storage(b))
        #expect(storage(a) != storage(c))
    }

    @Test("после разбора кэша книги одного автора делят список авторов")
    func decodeInterns() throws {
        let books = (1...3).map { i in
            Book(libid: Int32(i), title: "t", authorIDs: [Author.unknownID], seriesID: nil, seriesNum: nil,
                 genreIDs: [7], language: "ru", archiveIndex: 0, size: 0, dateAdded: nil)
        }
        let lib = Library(inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
                          authors: [Author.unknown], series: [],
                          genres: [Genre(id: 7, code: "g", name: "g", parentID: nil)], books: books)
        let decoded = try LibraryBinaryCodec.decode(LibraryBinaryCodec.encode(lib, sourceKey: Data(count: 32)))
        #expect(Set(decoded.books.map { storage($0.authorIDs) }).count == 1)
        #expect(Set(decoded.books.map { storage($0.genreIDs) }).count == 1)
    }

    @Test("Book без дыр выравнивания")
    func bookLayout() {
        #expect(MemoryLayout<Book>.stride <= 96)
    }
}
