import Testing
import Foundation
import Compression
@testable import FB_Loader

/// Собирает zip байтами: одна или несколько записей, без подписей CRC
/// (ридер CRC не проверяет). Смещения полей — по спецификации APPNOTE.
private struct ZipBuilder {
    struct Item {
        var name: String
        var payload: Data
        var deflate = false
        var flags: UInt16 = 0
    }

    var items: [Item]
    var comment = Data()

    /// Готовый архив и смещения, нужные тестам для порчи полей.
    struct Built {
        var data: Data
        var cdOffset: Int
        var eocdOffset: Int
        /// Смещения центральных заголовков записей.
        var cdHeaders: [Int]
    }

    func build() -> Built {
        var out = Data()
        var locals: [(Item, Data, Int)] = []
        for item in items {
            let body = item.deflate ? rawDeflate(item.payload) : item.payload
            let offset = out.count
            out.u32(0x04034b50); out.u16(20); out.u16(item.flags)
            out.u16(item.deflate ? 8 : 0); out.u16(0); out.u16(0)
            out.u32(0); out.u32(UInt32(body.count)); out.u32(UInt32(item.payload.count))
            out.u16(UInt16(item.name.utf8.count)); out.u16(0)
            out.append(Data(item.name.utf8)); out.append(body)
            locals.append((item, body, offset))
        }
        let cdOffset = out.count
        var cdHeaders: [Int] = []
        for (item, body, offset) in locals {
            cdHeaders.append(out.count)
            out.u32(0x02014b50); out.u16(20); out.u16(20); out.u16(item.flags)
            out.u16(item.deflate ? 8 : 0); out.u16(0); out.u16(0)
            out.u32(0); out.u32(UInt32(body.count)); out.u32(UInt32(item.payload.count))
            out.u16(UInt16(item.name.utf8.count)); out.u16(0); out.u16(0)
            out.u16(0); out.u16(0); out.u32(0); out.u32(UInt32(offset))
            out.append(Data(item.name.utf8))
        }
        let cdSize = out.count - cdOffset
        let eocdOffset = out.count
        out.u32(0x06054b50); out.u16(0); out.u16(0)
        out.u16(UInt16(items.count)); out.u16(UInt16(items.count))
        out.u32(UInt32(cdSize)); out.u32(UInt32(cdOffset))
        out.u16(UInt16(comment.count)); out.append(comment)
        return Built(data: out, cdOffset: cdOffset, eocdOffset: eocdOffset, cdHeaders: cdHeaders)
    }

    private func rawDeflate(_ src: Data) -> Data {
        var dst = Data(count: src.count + 1024)
        let n = dst.withUnsafeMutableBytes { d in
            src.withUnsafeBytes { s in
                compression_encode_buffer(d.bindMemory(to: UInt8.self).baseAddress!, d.count,
                                          s.bindMemory(to: UInt8.self).baseAddress!, s.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        return dst.prefix(n)
    }
}

private extension Data {
    mutating func u16(_ v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func u32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func put16(_ v: UInt16, at i: Int) {
        Swift.withUnsafeBytes(of: v.littleEndian) { replaceSubrange(i..<i + 2, with: $0) }
    }
    mutating func put32(_ v: UInt32, at i: Int) {
        Swift.withUnsafeBytes(of: v.littleEndian) { replaceSubrange(i..<i + 4, with: $0) }
    }
}

private let book = Data(String(repeating: "<FictionBook>текст</FictionBook>", count: 50).utf8)

@Suite("ZipCentralDirectory")
struct ZipCentralDirectoryTests {
    private let dir: URL = {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private func write(_ data: Data, name: String = "a.zip") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func extract(_ name: String, from url: URL) throws -> Data {
        let index = try ZipCentralDirectory.readIndex(of: url)
        let entry = try #require(index.entries[name])
        return try ZipCentralDirectory.extract(entry, from: url)
    }

    @Test("запись без сжатия читается")
    func stored() throws {
        let url = try write(ZipBuilder(items: [.init(name: "1.fb2", payload: book)]).build().data)
        #expect(try extract("1.fb2", from: url) == book)
    }

    @Test("запись со сжатием читается")
    func deflated() throws {
        let url = try write(ZipBuilder(items: [.init(name: "1.fb2", payload: book, deflate: true)]).build().data)
        #expect(try extract("1.fb2", from: url) == book)
    }

    @Test("сигнатура EOCD в последних 21 байте комментария не роняет разбор")
    func signatureInCommentTail() throws {
        var b = ZipBuilder(items: [.init(name: "1.fb2", payload: book)])
        b.comment = Data([0x00, 0x50, 0x4b, 0x05, 0x06, 0x00, 0x00])
        let url = try write(b.build().data)
        #expect(try extract("1.fb2", from: url) == book)
    }

    @Test("центральный каталог за пределами файла — ошибка")
    func cdBeyondFile() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book)]).build()
        built.data.put32(0xFFFF_FFF0, at: built.eocdOffset + 12)   // CD size
        let url = try write(built.data)
        #expect(throws: ZipCentralDirectory.ZipError.self) {
            try ZipCentralDirectory.readIndex(of: url)
        }
    }

    @Test("локальный заголовок за пределами файла — ошибка")
    func localHeaderBeyondFile() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book)]).build()
        built.data.put32(0x7FFF_FFF0, at: built.cdHeaders[0] + 42)
        let url = try write(built.data)
        #expect(throws: ZipCentralDirectory.ZipError.self) {
            try extract("1.fb2", from: url)
        }
    }

    @Test("заявленный размер больше предела — ошибка до выделения памяти")
    func entryTooLarge() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book, deflate: true)]).build()
        built.data.put32(0xFFFF_FFF0, at: built.cdHeaders[0] + 24) // uncompressed size
        let url = try write(built.data)
        let error = #expect(throws: ZipCentralDirectory.ZipError.self) {
            try extract("1.fb2", from: url)
        }
        guard case .entryTooLarge = error else {
            Issue.record("ожидалась entryTooLarge, получено \(String(describing: error))")
            return
        }
    }

    @Test("зашифрованная запись — ошибка encrypted")
    func encrypted() throws {
        let built = ZipBuilder(items: [.init(name: "1.fb2", payload: book, flags: 1)]).build()
        let url = try write(built.data)
        let error = #expect(throws: ZipCentralDirectory.ZipError.self) {
            try extract("1.fb2", from: url)
        }
        guard case .encrypted = error else {
            Issue.record("ожидалась encrypted, получено \(String(describing: error))")
            return
        }
    }

    @Test("битая запись посреди каталога — ошибка, а не обрезанный индекс")
    func corruptRecordMidDirectory() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book),
                                       .init(name: "2.fb2", payload: book)]).build()
        built.data.put32(0xDEAD_BEEF, at: built.cdHeaders[1])
        let url = try write(built.data)
        #expect(throws: ZipCentralDirectory.ZipError.self) {
            try ZipCentralDirectory.readIndex(of: url)
        }
    }

    @Test("маркеры ZIP64 без места под локатор — ошибка, а не переполнение")
    func zip64MarkersWithoutLocator() throws {
        var eocd = Data()
        eocd.u32(0x06054b50); eocd.u16(0); eocd.u16(0)
        eocd.u16(0xFFFF); eocd.u16(0xFFFF)
        eocd.u32(0xFFFF_FFFF); eocd.u32(0xFFFF_FFFF); eocd.u16(0)
        let url = try write(eocd)
        #expect(throws: ZipCentralDirectory.ZipError.self) {
            try ZipCentralDirectory.readIndex(of: url)
        }
    }

    @Test("слишком короткий файл — ошибка")
    func tooShort() throws {
        let url = try write(Data([0x50, 0x4b, 0x05, 0x06]))
        #expect(throws: ZipCentralDirectory.ZipError.self) {
            try ZipCentralDirectory.readIndex(of: url)
        }
    }
}

@Suite("ZipFB2Reader")
struct ZipFB2ReaderTests {
    @Test("подменённый на диске архив переиндексируется")
    func replacedArchiveReindexed() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("a.zip")

        let first = Data("первая".utf8)
        try ZipBuilder(items: [.init(name: "7.fb2", payload: first)]).build().data.write(to: url)
        #expect(try ZipFB2Reader.readFB2(libid: 7, archiveURL: url) == first)

        // Другая длина — другой размер файла, даже если mtime совпал до секунды.
        let second = Data("вторая, длиннее первой".utf8)
        try ZipBuilder(items: [.init(name: "0.fb2", payload: Data("x".utf8)),
                               .init(name: "7.fb2", payload: second)]).build().data.write(to: url)
        #expect(try ZipFB2Reader.readFB2(libid: 7, archiveURL: url) == second)
    }
}
