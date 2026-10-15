import Foundation
import Compression

/// Minimal ZIP reader optimized for the Flibusta case: 1–2 GB archives with
/// thousands of entries on slow external storage. ZIPFoundation 0.9.20's
/// `Archive.makeIterator` reads each central-directory record with a separate
/// disk seek, so finding one entry by name in such an archive takes ~20 s.
/// Here we read the *entire* central directory in one big chunk at archive
/// open (typically a few MB), build an in-memory `[name: Entry]` dict, and
/// extract entries by seeking directly to their local-file-header offset.
nonisolated enum ZipCentralDirectory {
    enum ZipError: Error {
        case eocdNotFound(URL)
        case truncated(URL)
        case unsupportedCompression(method: UInt16, name: String)
        case decompressionFailed(name: String)
        case entryNotFound(zip: URL, name: String)
        case entryTooLarge(name: String, size: UInt64)
        case encrypted(name: String)
    }

    /// Предел размера одной записи. FB2 с иллюстрациями — десятки мегабайт;
    /// всё, что больше, — битый или подсунутый архив, и буфер под заявленный
    /// размер выделять нельзя.
    static let maxEntrySize: UInt64 = 512 << 20

    struct Entry: Sendable {
        let name: String
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        /// Offset of the *local* file header in the zip file.
        let localHeaderOffset: UInt64
        /// 0 = stored (no compression), 8 = deflate.
        let compressionMethod: UInt16
        /// Бит 0 general purpose flags.
        let isEncrypted: Bool
    }

    /// In-memory snapshot of an archive's central directory.
    /// Cheap to keep around; one per zip file the user touches per session.
    struct Index: Sendable {
        let archiveURL: URL
        let entries: [String: Entry]
    }

    // MARK: - Index

    /// Reads central directory from the end of the zip and builds a name→entry map.
    /// O(CD size); for Flibusta archives this is one read of a few MB.
    static func readIndex(of url: URL) throws -> Index {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = (try handle.seekToEnd())
        guard fileSize >= 22 else { throw ZipError.eocdNotFound(url) }
        // EOCD record is variable-length (because of optional zip comment up to
        // 65535 bytes). It lives at the very end of the file. Read up to 64 KB
        // + the 22-byte EOCD header from the tail and scan back for the
        // signature 0x06054b50.
        let scanWindow: UInt64 = min(fileSize, 65557)
        try handle.seek(toOffset: fileSize - scanWindow)
        let tail = try readExactly(handle, Int(scanWindow), url)

        guard let eocdOffset = findLastSignature(in: tail, sig: 0x06054b50, recordSize: 22) else {
            throw ZipError.eocdNotFound(url)
        }

        // EOCD layout (offsets within tail starting at eocdOffset):
        //  +0  signature                 4 bytes
        //  +4  disk number               2
        //  +6  CD start disk             2
        //  +8  CD records on this disk   2
        //  +10 total CD records          2
        //  +12 CD size                   4
        //  +16 CD offset (from start)    4
        //  +20 comment length            2
        let eocd = tail.subdata(in: eocdOffset..<eocdOffset + 22)
        var cdSize64 = UInt64(readU32(eocd, 12))
        var cdOffset64 = UInt64(readU32(eocd, 16))
        var totalEntries64 = UInt64(readU16(eocd, 10))

        // ZIP64 EOCD locator may precede the regular EOCD (when sizes/offsets
        // exceed 32-bit limits). Real Flibusta archives are >2 GB, so this is
        // common. Locator signature is 0x07064b50, fixed 20 bytes immediately
        // before the regular EOCD.
        if cdOffset64 == 0xFFFF_FFFF || cdSize64 == 0xFFFF_FFFF || totalEntries64 == 0xFFFF {
            let eocdAbsOffset = (fileSize - scanWindow) + UInt64(eocdOffset)
            guard eocdAbsOffset >= 20 else { throw ZipError.truncated(url) }
            try handle.seek(toOffset: eocdAbsOffset - 20)
            let loc = try readExactly(handle, 20, url)
            guard readU32(loc, 0) == 0x07064b50 else {
                throw ZipError.truncated(url)
            }
            let zip64EocdOffset = readU64(loc, 8)
            guard fileSize >= 56, zip64EocdOffset <= fileSize - 56 else {
                throw ZipError.truncated(url)
            }
            try handle.seek(toOffset: zip64EocdOffset)
            // ZIP64 EOCD record starts with sig 0x06064b50, fixed 56-byte head.
            let z64 = try readExactly(handle, 56, url)
            guard readU32(z64, 0) == 0x06064b50 else {
                throw ZipError.truncated(url)
            }
            totalEntries64 = readU64(z64, 32)
            cdSize64 = readU64(z64, 40)
            cdOffset64 = readU64(z64, 48)
        }

        // Read the entire central directory in one go. Размер и смещение —
        // из файла, поэтому сначала проверка, что каталог в нём помещается:
        // иначе `Int(...)` трапает, а огромный размер — это гигантский буфер.
        guard cdOffset64 <= fileSize, cdSize64 <= fileSize - cdOffset64 else {
            throw ZipError.truncated(url)
        }
        try handle.seek(toOffset: cdOffset64)
        let cd = try readExactly(handle, Int(cdSize64), url)

        // Заявленному числу записей не верим: ёмкость — не больше, чем
        // записей минимального размера влезет в каталог.
        var entries = [String: Entry](minimumCapacity: Int(min(totalEntries64, cdSize64 / 46)))
        var p = 0
        while p + 46 <= cd.count {
            // Central file header layout:
            //  +0   sig 0x02014b50          4
            //  +8   general purpose flags   2
            //  +10  compression method      2
            //  +20  compressed size         4
            //  +24  uncompressed size       4
            //  +28  file name length        2
            //  +30  extra field length      2
            //  +32  file comment length     2
            //  +42  local header offset     4
            //  +46  file name
            // Битая запись посреди каталога — ошибка: молча обрезанный индекс
            // выдал бы «книга не найдена» для всех записей после неё.
            guard readU32(cd, p) == 0x02014b50 else { throw ZipError.truncated(url) }
            let flags = readU16(cd, p + 8)
            let method = readU16(cd, p + 10)
            var compressed = UInt64(readU32(cd, p + 20))
            var uncompressed = UInt64(readU32(cd, p + 24))
            let nameLen = Int(readU16(cd, p + 28))
            let extraLen = Int(readU16(cd, p + 30))
            let commentLen = Int(readU16(cd, p + 32))
            var localOffset = UInt64(readU32(cd, p + 42))

            let nameStart = p + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd <= cd.count else { throw ZipError.truncated(url) }
            let name = String(decoding: cd[nameStart..<nameEnd], as: UTF8.self)

            // Walk the extra field for ZIP64 size/offset overrides.
            if compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
                var ep = nameEnd
                let extraEnd = nameEnd + extraLen
                guard extraEnd <= cd.count else { throw ZipError.truncated(url) }
                while ep + 4 <= extraEnd {
                    let tag = readU16(cd, ep)
                    let size = Int(readU16(cd, ep + 2))
                    let fieldDataStart = ep + 4
                    let fieldEnd = fieldDataStart + size
                    guard fieldEnd <= extraEnd else { throw ZipError.truncated(url) }
                    if tag == 0x0001 {
                        var f = fieldDataStart
                        if uncompressed == 0xFFFF_FFFF {
                            guard f + 8 <= fieldEnd else { throw ZipError.truncated(url) }
                            uncompressed = readU64(cd, f); f += 8
                        }
                        if compressed == 0xFFFF_FFFF {
                            guard f + 8 <= fieldEnd else { throw ZipError.truncated(url) }
                            compressed = readU64(cd, f); f += 8
                        }
                        if localOffset == 0xFFFF_FFFF {
                            guard f + 8 <= fieldEnd else { throw ZipError.truncated(url) }
                            localOffset = readU64(cd, f)
                        }
                        break
                    }
                    ep += 4 + size
                }
            }

            entries[name] = Entry(
                name: name,
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                localHeaderOffset: localOffset,
                compressionMethod: method,
                isEncrypted: flags & 1 != 0
            )
            p = nameEnd + extraLen + commentLen
        }
        return Index(archiveURL: url, entries: entries)
    }

    // MARK: - Extract

    /// Reads and decompresses a single entry. Caller already has the index
    /// from `readIndex(of:)` and looked up the desired entry by name.
    static func extract(_ entry: Entry, from url: URL) throws -> Data {
        guard !entry.isEncrypted else { throw ZipError.encrypted(name: entry.name) }
        guard entry.uncompressedSize <= maxEntrySize, entry.compressedSize <= maxEntrySize else {
            throw ZipError.entryTooLarge(name: entry.name,
                                         size: max(entry.uncompressedSize, entry.compressedSize))
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()

        // Local file header layout (only the few fields we need):
        //  +0   sig 0x04034b50           4
        //  +26  file name length         2
        //  +28  extra field length       2
        //  +30  file name (variable)
        //  +30+nameLen+extraLen   start of compressed data
        guard fileSize >= 30, entry.localHeaderOffset <= fileSize - 30 else {
            throw ZipError.truncated(url)
        }
        try handle.seek(toOffset: entry.localHeaderOffset)
        let lhead = try readExactly(handle, 30, url)
        guard readU32(lhead, 0) == 0x04034b50 else {
            throw ZipError.truncated(url)
        }
        let nameLen = UInt64(readU16(lhead, 26))
        let extraLen = UInt64(readU16(lhead, 28))
        // Без переполнения: смещение ≤ fileSize − 30, длины — 16-битные.
        let dataStart = entry.localHeaderOffset + 30 + nameLen + extraLen
        guard dataStart <= fileSize, entry.compressedSize <= fileSize - dataStart else {
            throw ZipError.truncated(url)
        }
        try handle.seek(toOffset: dataStart)
        let compressed = try readExactly(handle, Int(entry.compressedSize), url)

        switch entry.compressionMethod {
        case 0:
            return compressed
        case 8:
            // Raw DEFLATE — no zlib wrapper. Apple's Compression framework
            // calls this `COMPRESSION_ZLIB`.
            return try inflate(deflate: compressed,
                               expected: Int(entry.uncompressedSize),
                               name: entry.name)
        default:
            throw ZipError.unsupportedCompression(method: entry.compressionMethod, name: entry.name)
        }
    }

    private static func inflate(deflate src: Data, expected: Int, name: String) throws -> Data {
        var out = Data(count: expected)
        let written: Int = try out.withUnsafeMutableBytes { (outBuf: UnsafeMutableRawBufferPointer) -> Int in
            try src.withUnsafeBytes { (inBuf: UnsafeRawBufferPointer) -> Int in
                guard let outBase = outBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let inBase = inBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    throw ZipError.decompressionFailed(name: name)
                }
                let n = compression_decode_buffer(outBase, expected,
                                                  inBase, src.count,
                                                  nil, COMPRESSION_ZLIB)
                if n == 0 || n != expected {
                    throw ZipError.decompressionFailed(name: name)
                }
                return n
            }
        }
        if written != expected { out.removeLast(out.count - written) }
        return out
    }

    // MARK: - Binary helpers

    /// Читает ровно `count` байт или бросает `truncated`. `read(upToCount:)`
    /// при ошибке ввода-вывода (отключённый внешний диск, уснувший NAS)
    /// бросает Swift-ошибку; устаревший `readData(ofLength:)` бросал
    /// Objective-C-исключение, которое `catch` не ловит, и ронял приложение.
    private static func readExactly(_ handle: FileHandle, _ count: Int, _ url: URL) throws -> Data {
        guard count > 0 else { return Data() }
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw ZipError.truncated(url)
        }
        return data
    }

    /// Последнее вхождение сигнатуры, после которого в данных помещается
    /// запись `recordSize` байт целиком.
    private static func findLastSignature(in data: Data, sig: UInt32, recordSize: Int) -> Int? {
        let bytes = [UInt8(truncatingIfNeeded: sig),
                     UInt8(truncatingIfNeeded: sig >> 8),
                     UInt8(truncatingIfNeeded: sig >> 16),
                     UInt8(truncatingIfNeeded: sig >> 24)]
        var i = data.count - recordSize
        while i >= 0 {
            if data[i] == bytes[0], data[i+1] == bytes[1],
               data[i+2] == bytes[2], data[i+3] == bytes[3] {
                return i
            }
            i -= 1
        }
        return nil
    }

    private static func readU16(_ d: Data, _ at: Int) -> UInt16 {
        UInt16(d[at]) | (UInt16(d[at+1]) << 8)
    }
    private static func readU32(_ d: Data, _ at: Int) -> UInt32 {
        UInt32(d[at]) | (UInt32(d[at+1]) << 8) | (UInt32(d[at+2]) << 16) | (UInt32(d[at+3]) << 24)
    }
    private static func readU64(_ d: Data, _ at: Int) -> UInt64 {
        UInt64(readU32(d, at)) | (UInt64(readU32(d, at + 4)) << 32)
    }
}
