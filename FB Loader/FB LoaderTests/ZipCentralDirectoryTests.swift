import Testing
import Foundation
import Compression
@testable import FB_Loader

/// Собирает zip байтами. Смещения полей — по спецификации APPNOTE.
private struct ZipBuilder {
    struct Item {
        var name: String
        var payload: Data
        var deflate = false
        var flags: UInt16 = 0
    }

    var items: [Item]
    var comment = Data()
    /// Писать ZIP64: маркеры в обычном EOCD, ZIP64 EOCD с локатором и
    /// смещение записи в extra-поле 0x0001.
    var zip64 = false
    /// Байты между центральным каталогом и EOCD (чужая запись в хвосте CD).
    var directoryTrailer = Data()

    /// Готовый архив и смещения, нужные тестам для порчи полей.
    struct Built {
        var data: Data
        var eocdOffset: Int
        /// Смещения центральных заголовков записей.
        var cdHeaders: [Int]
        /// Смещение ZIP64-локатора (только при `zip64`).
        var locatorOffset: Int?
    }

    func build() -> Built {
        var out = Data()
        var locals: [(Item, Data, Int)] = []
        for item in items {
            let body = item.deflate ? rawDeflate(item.payload) : item.payload
            let offset = out.count
            out.u32(0x04034b50); out.u16(20); out.u16(item.flags)
            out.u16(item.deflate ? 8 : 0); out.u16(0); out.u16(0)
            out.u32(CRC32.checksum(item.payload))
            out.u32(UInt32(body.count)); out.u32(UInt32(item.payload.count))
            out.u16(UInt16(item.name.utf8.count)); out.u16(0)
            out.append(Data(item.name.utf8)); out.append(body)
            locals.append((item, body, offset))
        }
        let cdOffset = out.count
        var cdHeaders: [Int] = []
        for (item, body, offset) in locals {
            cdHeaders.append(out.count)
            out.u32(0x02014b50); out.u16(45); out.u16(20); out.u16(item.flags)
            out.u16(item.deflate ? 8 : 0); out.u16(0); out.u16(0)
            out.u32(CRC32.checksum(item.payload))
            out.u32(UInt32(body.count)); out.u32(UInt32(item.payload.count))
            out.u16(UInt16(item.name.utf8.count)); out.u16(zip64 ? 12 : 0); out.u16(0)
            out.u16(0); out.u16(0); out.u32(0)
            out.u32(zip64 ? 0xFFFF_FFFF : UInt32(offset))
            out.append(Data(item.name.utf8))
            if zip64 {
                out.u16(0x0001); out.u16(8); out.u64(UInt64(offset))
            }
        }
        out.append(directoryTrailer)
        let cdSize = out.count - cdOffset

        var locatorOffset: Int?
        if zip64 {
            let z64Offset = out.count
            out.u32(0x06064b50); out.u64(44); out.u16(45); out.u16(45)
            out.u32(0); out.u32(0)
            out.u64(UInt64(items.count)); out.u64(UInt64(items.count))
            out.u64(UInt64(cdSize)); out.u64(UInt64(cdOffset))
            locatorOffset = out.count
            out.u32(0x07064b50); out.u32(0); out.u64(UInt64(z64Offset)); out.u32(1)
        }

        let eocdOffset = out.count
        out.u32(0x06054b50); out.u16(0); out.u16(0)
        let count16: UInt16 = zip64 ? 0xFFFF : UInt16(items.count)
        out.u16(count16); out.u16(count16)
        out.u32(zip64 ? 0xFFFF_FFFF : UInt32(cdSize))
        out.u32(zip64 ? 0xFFFF_FFFF : UInt32(cdOffset))
        out.u16(UInt16(comment.count)); out.append(comment)
        return Built(data: out, eocdOffset: eocdOffset, cdHeaders: cdHeaders,
                     locatorOffset: locatorOffset)
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
    mutating func u64(_ v: UInt64) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func put16(_ v: UInt16, at i: Int) {
        Swift.withUnsafeBytes(of: v.littleEndian) { replaceSubrange(i..<i + 2, with: $0) }
    }
    mutating func put32(_ v: UInt32, at i: Int) {
        Swift.withUnsafeBytes(of: v.littleEndian) { replaceSubrange(i..<i + 4, with: $0) }
    }
    mutating func put64(_ v: UInt64, at i: Int) {
        Swift.withUnsafeBytes(of: v.littleEndian) { replaceSubrange(i..<i + 8, with: $0) }
    }
}

private let book = Data(String(repeating: "<FictionBook>текст</FictionBook>", count: 50).utf8)

/// Проверяет, что `body` бросает `ZipError` нужного вида.
private func expectZipError(_ matches: (ZipCentralDirectory.ZipError) -> Bool,
                            sourceLocation: SourceLocation = #_sourceLocation,
                            _ body: () throws -> Void) {
    let error = #expect(throws: ZipCentralDirectory.ZipError.self, sourceLocation: sourceLocation) {
        try body()
    }
    if let error, !matches(error) {
        Issue.record("неожиданная ошибка \(error)", sourceLocation: sourceLocation)
    }
}

@Suite("ZipCentralDirectory")
final class ZipCentralDirectoryTests {
    private let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ data: Data) throws -> URL {
        let url = dir.appendingPathComponent("a.zip")
        try data.write(to: url)
        return url
    }

    private func extract(_ name: String, from url: URL) throws -> Data {
        let index = try ZipCentralDirectory.readIndex(of: url)
        let entry = try #require(index.entries[name])
        return try ZipCentralDirectory.extract(entry, from: url)
    }

    // MARK: Нормальные архивы

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

    @Test("ZIP64-архив читается")
    func zip64() throws {
        var b = ZipBuilder(items: [.init(name: "1.fb2", payload: book),
                                   .init(name: "2.fb2", payload: book, deflate: true)])
        b.zip64 = true
        let url = try write(b.build().data)
        #expect(try extract("1.fb2", from: url) == book)
        #expect(try extract("2.fb2", from: url) == book)
    }

    @Test("сигнатура EOCD в последних 21 байте комментария не роняет разбор")
    func signatureInCommentTail() throws {
        var b = ZipBuilder(items: [.init(name: "1.fb2", payload: book)])
        b.comment = Data([0x00, 0x50, 0x4b, 0x05, 0x06, 0x00, 0x00])
        let url = try write(b.build().data)
        #expect(try extract("1.fb2", from: url) == book)
    }

    @Test("чужая запись после всех записей каталога допустима")
    func trailingRecordAfterDirectory() throws {
        var b = ZipBuilder(items: [.init(name: "1.fb2", payload: book)])
        var signature = Data()
        signature.u32(0x05054b50); signature.u16(40)
        signature.append(Data(repeating: 0, count: 40))
        b.directoryTrailer = signature
        let url = try write(b.build().data)
        #expect(try extract("1.fb2", from: url) == book)
    }

    @Test("ровно 65535 записей без ZIP64 — обычный архив, а не ошибка")
    func entryCountMarkerWithoutZip64() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book)]).build()
        built.data.put16(0xFFFF, at: built.eocdOffset + 8)
        built.data.put16(0xFFFF, at: built.eocdOffset + 10)
        let url = try write(built.data)
        #expect(try extract("1.fb2", from: url) == book)
    }

    // MARK: Битые архивы

    @Test("слишком короткий файл — ошибка")
    func tooShort() throws {
        let url = try write(Data([0x50, 0x4b, 0x05, 0x06]))
        expectZipError({ if case .eocdNotFound = $0 { true } else { false } }) {
            _ = try ZipCentralDirectory.readIndex(of: url)
        }
    }

    @Test("размер каталога за пределами файла — ошибка")
    func cdSizeBeyondFile() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book)]).build()
        built.data.put32(0xFFFF_FFF0, at: built.eocdOffset + 12)
        let url = try write(built.data)
        expectZipError({ if case .truncated = $0 { true } else { false } }) {
            _ = try ZipCentralDirectory.readIndex(of: url)
        }
    }

    @Test("смещение каталога за пределами файла — ошибка")
    func cdOffsetBeyondFile() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book)]).build()
        built.data.put32(0x7FFF_FFF0, at: built.eocdOffset + 16)
        let url = try write(built.data)
        expectZipError({ if case .truncated = $0 { true } else { false } }) {
            _ = try ZipCentralDirectory.readIndex(of: url)
        }
    }

    @Test("маркеры ZIP64 без места под локатор — ошибка, а не переполнение")
    func zip64MarkersWithoutLocator() throws {
        var eocd = Data()
        eocd.u32(0x06054b50); eocd.u16(0); eocd.u16(0)
        eocd.u16(0xFFFF); eocd.u16(0xFFFF)
        eocd.u32(0xFFFF_FFFF); eocd.u32(0xFFFF_FFFF); eocd.u16(0)
        let url = try write(eocd)
        expectZipError({ if case .truncated = $0 { true } else { false } }) {
            _ = try ZipCentralDirectory.readIndex(of: url)
        }
    }

    @Test("ZIP64 EOCD за пределами файла — ошибка")
    func zip64EocdBeyondFile() throws {
        var b = ZipBuilder(items: [.init(name: "1.fb2", payload: book)])
        b.zip64 = true
        var built = b.build()
        built.data.put64(0x7FFF_FFFF_FFFF, at: try #require(built.locatorOffset) + 8)
        let url = try write(built.data)
        expectZipError({ if case .truncated = $0 { true } else { false } }) {
            _ = try ZipCentralDirectory.readIndex(of: url)
        }
    }

    @Test("обрезанное ZIP64 extra-поле — ошибка")
    func truncatedZip64Extra() throws {
        var b = ZipBuilder(items: [.init(name: "1.fb2", payload: book)])
        b.zip64 = true
        var built = b.build()
        // Длина данных поля 0x0001: 4 вместо 8 — смещение не помещается.
        let extraStart = built.cdHeaders[0] + 46 + "1.fb2".utf8.count
        built.data.put16(4, at: extraStart + 2)
        let url = try write(built.data)
        expectZipError({ if case .truncated = $0 { true } else { false } }) {
            _ = try ZipCentralDirectory.readIndex(of: url)
        }
    }

    @Test("битая запись посреди каталога — ошибка, а не обрезанный индекс")
    func corruptRecordMidDirectory() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book),
                                       .init(name: "2.fb2", payload: book)]).build()
        built.data.put32(0xDEAD_BEEF, at: built.cdHeaders[1])
        let url = try write(built.data)
        expectZipError({ if case .truncated = $0 { true } else { false } }) {
            _ = try ZipCentralDirectory.readIndex(of: url)
        }
    }

    @Test("имя записи выходит за каталог — ошибка")
    func nameBeyondDirectory() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book)]).build()
        built.data.put16(0xFFF0, at: built.cdHeaders[0] + 28)
        let url = try write(built.data)
        expectZipError({ if case .truncated = $0 { true } else { false } }) {
            _ = try ZipCentralDirectory.readIndex(of: url)
        }
    }

    @Test("локальный заголовок за пределами файла — ошибка")
    func localHeaderBeyondFile() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book)]).build()
        built.data.put32(0x7FFF_FFF0, at: built.cdHeaders[0] + 42)
        let url = try write(built.data)
        expectZipError({ if case .truncated = $0 { true } else { false } }) {
            _ = try self.extract("1.fb2", from: url)
        }
    }

    @Test("заявленный размер больше предела — ошибка до выделения памяти")
    func entryTooLarge() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book, deflate: true)]).build()
        built.data.put32(0xFFFF_FFF0, at: built.cdHeaders[0] + 24)
        let url = try write(built.data)
        expectZipError({ if case .entryTooLarge = $0 { true } else { false } }) {
            _ = try self.extract("1.fb2", from: url)
        }
    }

    @Test("зашифрованная запись — ошибка encrypted")
    func encrypted() throws {
        let url = try write(ZipBuilder(items: [.init(name: "1.fb2", payload: book, flags: 1)]).build().data)
        expectZipError({ if case .encrypted = $0 { true } else { false } }) {
            _ = try self.extract("1.fb2", from: url)
        }
    }

    @Test("неподдерживаемый метод сжатия — ошибка")
    func unsupportedMethod() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book)]).build()
        built.data.put16(12, at: built.cdHeaders[0] + 10)
        let url = try write(built.data)
        expectZipError({ if case .unsupportedCompression(method: 12, _) = $0 { true } else { false } }) {
            _ = try self.extract("1.fb2", from: url)
        }
    }

    @Test("заниженный распакованный размер — ошибка, а не обрезанная книга")
    func understatedSize() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book, deflate: true)]).build()
        built.data.put32(UInt32(book.count / 2), at: built.cdHeaders[0] + 24)
        let url = try write(built.data)
        expectZipError({
            switch $0 {
            case .decompressionFailed, .checksumMismatch: true
            default: false
            }
        }) {
            _ = try self.extract("1.fb2", from: url)
        }
    }

    @Test("повреждённые данные без сжатия — ошибка контрольной суммы")
    func corruptStoredData() throws {
        var built = ZipBuilder(items: [.init(name: "1.fb2", payload: book)]).build()
        let dataStart = 30 + "1.fb2".utf8.count
        built.data[dataStart + 10] ^= 0xFF
        let url = try write(built.data)
        expectZipError({ if case .checksumMismatch = $0 { true } else { false } }) {
            _ = try self.extract("1.fb2", from: url)
        }
    }
}

@Suite("CRC32")
struct CRC32Tests {
    @Test("контрольное значение IEEE для «123456789»")
    func checkValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
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
