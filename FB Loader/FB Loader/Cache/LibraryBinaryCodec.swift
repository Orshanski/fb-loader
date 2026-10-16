import Foundation

/// Binary on-disk format:
///   "FBLC"   4B    magic
///   version  uint16 (current = 4)
///   inpxHash 32B
///   sourceKey 32B — версия импортёра и genres.json (`LibraryCacheStore.sourceKey`)
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
///       dateAdded float64 — timeIntervalSinceReferenceDate, NaN = нет даты
///       archiveFileName len(uint16) + utf8, пусто = nil
nonisolated enum LibraryBinaryCodec {
    enum DecodeError: Error {
        case badMagic
        case unsupportedVersion(UInt16)
        case truncated
        case invalidArchiveIndex(libid: Int32, archiveIndex: Int16, archivesCount: Int)
        case inconsistent(String)
    }
    enum EncodeError: Error {
        /// Thrown instead of `precondition`: one oversized string must not crash the process.
        case stringTooLong(field: String, length: Int, max: Int)
        case tooManyItems(field: String, count: Int, max: Int)
        case invalidHashSize(Int)
    }

    static let headerSize = 70

    struct Header: Equatable {
        let inpxHash: Data
        let sourceKey: Data
    }

    private static let magic: [UInt8] = Array("FBLC".utf8)
    /// Bump on any layout change: old caches throw `unsupportedVersion` and `LibraryCacheStore` reparses.
    private static let formatVersion: UInt16 = 4

    static func encode(_ lib: Library, sourceKey: Data) throws -> Data {
        var w = BinaryWriter()
        w.bytes(magic)
        w.uint16(formatVersion)
        for hash in [lib.inpxHash, sourceKey] {
            guard hash.count == 32 else { throw EncodeError.invalidHashSize(hash.count) }
            w.bytes(Array(hash))
        }
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
            try w.count16(b.authorIDs.count, field: "book.authorIDs")
            for id in b.authorIDs { w.int32(id) }
            w.int32(b.seriesID ?? -1)
            w.int16(b.seriesNum ?? Int16.min)
            try w.count16(b.genreIDs.count, field: "book.genreIDs")
            for g in b.genreIDs { w.int16(g) }
            try w.string8(b.language, field: "book.language")
            w.int16(b.archiveIndex)
            w.int32(b.size)
            w.double(b.dateAdded?.timeIntervalSinceReferenceDate ?? .nan)
            try w.string16(b.archiveFileName ?? "", field: "book.archiveFileName")
        }
        return w.data
    }

    static func readHeader(_ data: Data) throws -> Header {
        var r = BinaryReader(data: data)
        return try readHeader(&r)
    }

    private static func readHeader(_ r: inout BinaryReader) throws -> Header {
        guard try r.bytes(4) == magic else { throw DecodeError.badMagic }
        let v = try r.uint16()
        guard v == formatVersion else { throw DecodeError.unsupportedVersion(v) }
        return Header(inpxHash: Data(try r.bytes(32)), sourceKey: Data(try r.bytes(32)))
    }

    static func decode(_ data: Data, onStatus: (@Sendable (String) -> Void)? = nil) throws -> Library {
        var r = BinaryReader(data: data)
        let inpxHash = try readHeader(&r).inpxHash
        let inpxVersion = try r.string16()
        let archCount = try r.uint32()
        var archives: [String] = []
        archives.reserveCapacity(r.capacity(archCount, minSize: 2))
        for _ in 0..<archCount { archives.append(try r.string16()) }
        let authCount = try r.uint32()
        var authors: [Author] = []
        authors.reserveCapacity(r.capacity(authCount, minSize: 10))
        for _ in 0..<authCount {
            let id = try r.int32()
            let ln = try r.string16(); let fn = try r.string16(); let mn = try r.string16()
            authors.append(Author(id: id, lastName: ln, firstName: fn, middleName: mn))
        }
        let serCount = try r.uint32()
        var series: [Series] = []
        series.reserveCapacity(r.capacity(serCount, minSize: 6))
        for _ in 0..<serCount {
            series.append(Series(id: try r.int32(), name: try r.string16()))
        }
        let genCount = try r.uint32()
        var genres: [Genre] = []
        genres.reserveCapacity(r.capacity(genCount, minSize: 10))
        for _ in 0..<genCount {
            let id = try r.int16(); let code = try r.string16(); let name = try r.string16()
            let p = try r.int32()
            let parent: Int16?
            if p == -1 {
                parent = nil
            } else if let p16 = Int16(exactly: p) {
                parent = p16
            } else {
                throw DecodeError.inconsistent("genre \(id): parentID \(p)")
            }
            genres.append(Genre(id: id, code: code, name: name, parentID: parent))
        }
        let bookCount = try r.uint32()
        var books: [Book] = []
        books.reserveCapacity(r.capacity(bookCount, minSize: 33))
        var authorLists = Interner<Int32>(), genreLists = Interner<Int16>()
        for _ in 0..<bookCount {
            let libid = try r.int32()
            let title = try r.string16()
            let aCount = try r.uint16()
            var aIDs: [Int32] = []; aIDs.reserveCapacity(r.capacity(UInt32(aCount), minSize: 4))
            for _ in 0..<aCount { aIDs.append(try r.int32()) }
            let s = try r.int32()
            let sn = try r.int16()
            let gCount = try r.uint16()
            var gIDs: [Int16] = []; gIDs.reserveCapacity(r.capacity(UInt32(gCount), minSize: 2))
            for _ in 0..<gCount { gIDs.append(try r.int16()) }
            let lang = try r.string8()
            let archIdx = try r.int16()
            let size = try r.int32()
            let dateSeconds = try r.double()
            let fileName = try r.string16()
            guard archIdx >= 0 && Int(archIdx) < archives.count else {
                throw DecodeError.invalidArchiveIndex(
                    libid: libid,
                    archiveIndex: archIdx,
                    archivesCount: archives.count)
            }
            books.append(Book(
                libid: libid, title: title, authorIDs: authorLists.intern(aIDs),
                seriesID: s == -1 ? nil : s,
                seriesNum: sn == Int16.min ? nil : sn,
                genreIDs: genreLists.intern(gIDs), language: lang, archiveIndex: archIdx,
                size: size,
                dateAdded: dateSeconds.isNaN
                    ? nil
                    : Date(timeIntervalSinceReferenceDate: dateSeconds),
                archiveFileName: fileName.isEmpty ? nil : fileName
            ))
        }
        try validate(authors: authors, series: series, genres: genres, books: books)
        return Library(
            inpxHash: inpxHash,
            inpxVersion: inpxVersion,
            archives: archives,
            authors: authors,
            series: series,
            genres: genres,
            books: books,
            onStatus: onStatus
        )
    }

    static func validate(authors: [Author], series: [Series], genres: [Genre], books: [Book]) throws {
        var authorIDs = Set<Int32>()
        for a in authors where !authorIDs.insert(a.id).inserted {
            throw DecodeError.inconsistent("author id \(a.id) repeated")
        }
        var seriesIDs = Set<Int32>()
        for s in series where !seriesIDs.insert(s.id).inserted {
            throw DecodeError.inconsistent("series id \(s.id) repeated")
        }
        var genreIDs = Set<Int16>()
        for g in genres where !genreIDs.insert(g.id).inserted {
            throw DecodeError.inconsistent("genre id \(g.id) repeated")
        }
        for b in books {
            if let a = b.authorIDs.first(where: { !authorIDs.contains($0) }) {
                throw DecodeError.inconsistent("book \(b.libid): author \(a)")
            }
            if let s = b.seriesID, !seriesIDs.contains(s) {
                throw DecodeError.inconsistent("book \(b.libid): series \(s)")
            }
            if let g = b.genreIDs.first(where: { !genreIDs.contains($0) }) {
                throw DecodeError.inconsistent("book \(b.libid): genre \(g)")
            }
        }
    }
}

private nonisolated struct BinaryWriter {
    var data = Data()
    mutating func bytes(_ b: [UInt8]) { data.append(contentsOf: b) }
    mutating func uint16(_ v: UInt16) { var v = v.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    mutating func uint32(_ v: UInt32) { var v = v.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    mutating func int16(_ v: Int16)   { var v = v.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    mutating func int32(_ v: Int32)   { var v = v.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    mutating func double(_ v: Double) { uint64(v.bitPattern) }
    mutating func uint64(_ v: UInt64) { var v = v.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    mutating func count16(_ n: Int, field: String) throws {
        guard let v = UInt16(exactly: n) else {
            throw LibraryBinaryCodec.EncodeError.tooManyItems(
                field: field, count: n, max: Int(UInt16.max))
        }
        uint16(v)
    }
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
    func capacity(_ count: UInt32, minSize: Int) -> Int {
        min(Int(count), (data.count - offset) / minSize)
    }
    mutating func bytes(_ n: Int) throws -> [UInt8] {
        let at = data.startIndex + (try advance(n))
        return Array(data[at..<at + n])
    }
    /// Без временного массива на значение — их миллионы на загрузку.
    private mutating func advance(_ n: Int) throws -> Int {
        guard offset + n <= data.count else { throw LibraryBinaryCodec.DecodeError.truncated }
        defer { offset += n }
        return offset
    }
    private func byte(_ i: Int) -> UInt64 { UInt64(data[data.startIndex + i]) }
    private mutating func littleEndian(_ n: Int) throws -> UInt64 {
        let at = try advance(n)
        var v: UInt64 = 0
        for i in (0..<n).reversed() { v = (v << 8) | byte(at + i) }
        return v
    }
    mutating func uint8() throws -> UInt8 { UInt8(try littleEndian(1)) }
    mutating func uint16() throws -> UInt16 { UInt16(try littleEndian(2)) }
    mutating func uint32() throws -> UInt32 { UInt32(try littleEndian(4)) }
    mutating func int16() throws -> Int16 { Int16(bitPattern: try uint16()) }
    mutating func int32() throws -> Int32 { Int32(bitPattern: try uint32()) }
    mutating func uint64() throws -> UInt64 { try littleEndian(8) }
    mutating func double() throws -> Double { Double(bitPattern: try uint64()) }
    mutating func string16() throws -> String { try string(length: Int(try uint16())) }
    mutating func string8() throws -> String { try string(length: Int(try uint8())) }
    private mutating func string(length n: Int) throws -> String {
        let at = data.startIndex + (try advance(n))
        return String(decoding: data[at..<at + n], as: UTF8.self)
    }
}
