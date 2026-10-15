import Foundation
import Compression
@testable import FB_Loader

/// Собирает zip байтами. Смещения полей — по спецификации APPNOTE.
struct ZipBuilder {
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

/// Синтетический INPX: version.info, необязательный structure.info и один .inp.
enum INPXFixture {
    static func make(in dir: URL,
                     lines: [String],
                     lineEnding: String = "\r\n",
                     inpName: String = "lib-001.inp",
                     structure: String? = nil) throws -> URL {
        var items: [ZipBuilder.Item] = [
            .init(name: "version.info", payload: Data("20261015".utf8)),
        ]
        if let structure {
            items.append(.init(name: "structure.info", payload: Data(structure.utf8)))
        }
        let text = lines.joined(separator: lineEnding) + lineEnding
        items.append(.init(name: inpName, payload: Data(text.utf8), deflate: true))
        let url = dir.appendingPathComponent("\(UUID().uuidString).inpx")
        try ZipBuilder(items: items).build().data.write(to: url)
        return url
    }

    /// Строка .inp в раскладке по умолчанию (AUTHOR;GENRE;TITLE;SERIES;SERNO;
    /// FILE;SIZE;LIBID;DEL;EXT;DATE;LANG).
    static func line(author: String = "Толстой,Лев,Николаевич:",
                     genre: String = "prose_classic:",
                     title: String = "Война и мир",
                     series: String = "",
                     serno: String = "",
                     file: String? = nil,
                     size: String = "1000",
                     libid: String,
                     deleted: String = "0",
                     ext: String = "fb2",
                     date: String = "2010-05-15",
                     lang: String = "ru") -> String {
        [author, genre, title, series, serno, file ?? libid, size, libid,
         deleted, ext, date, lang].joined(separator: "\u{04}")
    }
}

extension Data {
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
