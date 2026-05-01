import Foundation

/// Binary on-disk format:
///   "FBLC"   4B    magic
///   version  uint16 (current = 1)
///   inpxHash 32B
///   inpxVersionLen uint16, inpxVersion utf8 bytes
///   archivesCount uint32, then for each: len(uint16) + utf8 bytes
///   authorsCount uint32, then for each:
///       id int32; lastName, firstName, middleName (len uint16 + utf8)
///   seriesCount uint32, then for each: id int32; name (len uint16 + utf8)
///   genresCount uint32, then for each: id int16; code; name; parentID int32 (-1 = nil)
///   booksCount uint32, then for each:
///       libid int32; title len+utf8;
///       authorIDs count(uint16) + ints32
///       seriesID int32 (-1=nil); seriesNum int16 (Int16.min=nil)
///       genreIDs count(uint16) + ints16
///       language len(uint8) + utf8
///       archiveIndex int16
///       size int32
///       dateAddedDays int32
nonisolated enum LibraryBinaryCodec {
    enum DecodeError: Error {
        case badMagic
        case unsupportedVersion(UInt16)
        case truncated
    }
    enum EncodeError: Error {
        /// Signalled instead of `precondition` to avoid crashing the whole process
        /// if a single book's title (or other length-prefixed string) exceeds
        /// the on-disk format's length encoding capacity.
        case stringTooLong(field: String, length: Int, max: Int)
        /// `inpxHash` must always be 32 bytes (SHA-256). A different size would
        /// silently corrupt every field after it on decode (the decoder reads
        /// exactly 32 bytes regardless), so we throw at encode time instead.
        case invalidHashSize(Int)
    }

    private static let magic: [UInt8] = Array("FBLC".utf8)
    /// Bumped from 1 → 2 to invalidate caches built before the CRLF parser
    /// fix (262e3bf), which silently produced 1-book-per-.inp catalogs.
    /// Old caches decode → `unsupportedVersion(1)` → `LibraryCacheStore`
    /// falls through to reparse on the next launch.
    private static let formatVersion: UInt16 = 2

    static func encode(_ lib: Library) throws -> Data {
        var w = BinaryWriter()
        w.bytes(magic)
        w.uint16(formatVersion)
        guard lib.inpxHash.count == 32 else {
            throw EncodeError.invalidHashSize(lib.inpxHash.count)
        }
        w.bytes(Array(lib.inpxHash))
        try w.string16(lib.inpxVersion, field: "inpxVersion")
        w.uint32(UInt32(lib.archives.count))
        for s in lib.archives { try w.string16(s, field: "archive") }
        w.uint32(UInt32(lib.authors.count))
        for a in lib.authors {
            w.int32(a.id)
            try w.string16(a.lastName, field: "author.lastName")
            try w.string16(a.firstName, field: "author.firstName")
            try w.string16(a.middleName, field: "author.middleName")
        }
        w.uint32(UInt32(lib.series.count))
        for s in lib.series {
            w.int32(s.id); try w.string16(s.name, field: "series.name")
        }
        w.uint32(UInt32(lib.genres.count))
        for g in lib.genres {
            w.int16(g.id)
            try w.string16(g.code, field: "genre.code")
            try w.string16(g.name, field: "genre.name")
            w.int32(g.parentID.map(Int32.init) ?? -1)
        }
        w.uint32(UInt32(lib.books.count))
        for b in lib.books {
            w.int32(b.libid)
            try w.string16(b.title, field: "book.title")
            w.uint16(UInt16(b.authorIDs.count))
            for id in b.authorIDs { w.int32(id) }
            w.int32(b.seriesID ?? -1)
            w.int16(b.seriesNum ?? Int16.min)
            w.uint16(UInt16(b.genreIDs.count))
            for g in b.genreIDs { w.int16(g) }
            try w.string8(b.language, field: "book.language")
            w.int16(b.archiveIndex)
            w.int32(b.size)
            w.int32(b.dateAddedDays)
        }
        return w.data
    }

    static func decode(_ data: Data) throws -> Library {
        var r = BinaryReader(data: data)
        guard try r.bytes(4) == magic else { throw DecodeError.badMagic }
        let v = try r.uint16()
        guard v == formatVersion else { throw DecodeError.unsupportedVersion(v) }
        let inpxHash = Data(try r.bytes(32))
        let inpxVersion = try r.string16()
        let archCount = try r.uint32()
        var archives: [String] = []
        archives.reserveCapacity(Int(archCount))
        for _ in 0..<archCount { archives.append(try r.string16()) }
        let authCount = try r.uint32()
        var authors: [Author] = []
        authors.reserveCapacity(Int(authCount))
        for _ in 0..<authCount {
            let id = try r.int32()
            let ln = try r.string16(); let fn = try r.string16(); let mn = try r.string16()
            authors.append(Author(id: id, lastName: ln, firstName: fn, middleName: mn))
        }
        let serCount = try r.uint32()
        var series: [Series] = []
        series.reserveCapacity(Int(serCount))
        for _ in 0..<serCount {
            series.append(Series(id: try r.int32(), name: try r.string16()))
        }
        let genCount = try r.uint32()
        var genres: [Genre] = []
        genres.reserveCapacity(Int(genCount))
        for _ in 0..<genCount {
            let id = try r.int16(); let code = try r.string16(); let name = try r.string16()
            let p = try r.int32()
            genres.append(Genre(id: id, code: code, name: name,
                                parentID: p == -1 ? nil : Int16(p)))
        }
        let bookCount = try r.uint32()
        var books: [Book] = []
        books.reserveCapacity(Int(bookCount))
        for _ in 0..<bookCount {
            let libid = try r.int32()
            let title = try r.string16()
            let aCount = try r.uint16()
            var aIDs: [Int32] = []; aIDs.reserveCapacity(Int(aCount))
            for _ in 0..<aCount { aIDs.append(try r.int32()) }
            let s = try r.int32()
            let sn = try r.int16()
            let gCount = try r.uint16()
            var gIDs: [Int16] = []; gIDs.reserveCapacity(Int(gCount))
            for _ in 0..<gCount { gIDs.append(try r.int16()) }
            let lang = try r.string8()
            let archIdx = try r.int16()
            let size = try r.int32()
            let days = try r.int32()
            books.append(Book(
                libid: libid, title: title, authorIDs: aIDs,
                seriesID: s == -1 ? nil : s,
                seriesNum: sn == Int16.min ? nil : sn,
                genreIDs: gIDs, language: lang, archiveIndex: archIdx,
                size: size, dateAddedDays: days
            ))
        }
        return Library(
            inpxHash: inpxHash,
            inpxVersion: inpxVersion,
            archives: archives,
            authors: authors,
            series: series,
            genres: genres,
            books: books
        )
    }
}

private nonisolated struct BinaryWriter {
    var data = Data()
    mutating func bytes(_ b: [UInt8]) { data.append(contentsOf: b) }
    mutating func uint16(_ v: UInt16) { var v = v.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    mutating func uint32(_ v: UInt32) { var v = v.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    mutating func int16(_ v: Int16)   { var v = v.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    mutating func int32(_ v: Int32)   { var v = v.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    mutating func string16(_ s: String, field: String) throws {
        let utf = Array(s.utf8)
        guard utf.count <= Int(UInt16.max) else {
            throw LibraryBinaryCodec.EncodeError.stringTooLong(
                field: field, length: utf.count, max: Int(UInt16.max))
        }
        uint16(UInt16(utf.count))
        bytes(utf)
    }
    mutating func string8(_ s: String, field: String) throws {
        let utf = Array(s.utf8)
        guard utf.count <= Int(UInt8.max) else {
            throw LibraryBinaryCodec.EncodeError.stringTooLong(
                field: field, length: utf.count, max: Int(UInt8.max))
        }
        var len = UInt8(utf.count); withUnsafeBytes(of: &len) { data.append(contentsOf: $0) }
        bytes(utf)
    }
}

private nonisolated struct BinaryReader {
    let data: Data
    var offset: Int = 0
    init(data: Data) { self.data = data }
    mutating func bytes(_ n: Int) throws -> [UInt8] {
        guard offset + n <= data.count else { throw LibraryBinaryCodec.DecodeError.truncated }
        defer { offset += n }
        return Array(data[offset..<offset+n])
    }
    mutating func uint8() throws -> UInt8 { (try bytes(1))[0] }
    mutating func uint16() throws -> UInt16 {
        let b = try bytes(2)
        return UInt16(b[0]) | (UInt16(b[1]) << 8)
    }
    mutating func uint32() throws -> UInt32 {
        let b = try bytes(4)
        return UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
    }
    mutating func int16() throws -> Int16 { Int16(bitPattern: try uint16()) }
    mutating func int32() throws -> Int32 { Int32(bitPattern: try uint32()) }
    mutating func string16() throws -> String {
        let n = try uint16()
        let b = try bytes(Int(n))
        return String(decoding: b, as: UTF8.self)
    }
    mutating func string8() throws -> String {
        let n = try uint8()
        let b = try bytes(Int(n))
        return String(decoding: b, as: UTF8.self)
    }
}
