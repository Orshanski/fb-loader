import Testing
import Foundation
import Compression
@testable import FB_Loader

private let book = Data(String(repeating: "<FictionBook>текст</FictionBook>", count: 50).utf8)

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
        #expect(try ZipFB2Reader.readFB2(entryName: "7.fb2", archiveURL: url) == first)

        // Другая длина — другой размер файла, даже если mtime совпал до секунды.
        let second = Data("вторая, длиннее первой".utf8)
        try ZipBuilder(items: [.init(name: "0.fb2", payload: Data("x".utf8)),
                               .init(name: "7.fb2", payload: second)]).build().data.write(to: url)
        #expect(try ZipFB2Reader.readFB2(entryName: "7.fb2", archiveURL: url) == second)
    }
}
