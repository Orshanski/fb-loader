import Testing
import Foundation
@testable import FB_Loader

@Suite("ExportRunner")
@MainActor
final class ExportRunnerTests {
    private let dir: URL
    private let archives: URL
    private let out: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        archives = dir.appendingPathComponent("archives", isDirectory: true)
        out = dir.appendingPathComponent("out", isDirectory: true)
        for url in [archives, out] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: out.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func payload(_ libid: Int32) -> Data { Data("<FictionBook>\(libid)</FictionBook>".utf8) }

    /// Архив `present.zip` содержит книги архива 0, кроме `absent`; `missing.zip` на диске нет.
    private func library(_ books: [(libid: Int32, title: String, archive: Int16)],
                         absent: Set<Int32> = []) throws -> Library {
        let items = books.filter { $0.archive == 0 && !absent.contains($0.libid) }
            .map { ZipBuilder.Item(name: "\($0.libid).fb2", payload: payload($0.libid)) }
        try ZipBuilder(items: items).build().data.write(to: archives.appendingPathComponent("present.zip"))
        let authors = [Author.unknown, Author(id: 1, lastName: "Толстой", firstName: "Лев", middleName: "")]
        let list = books.map {
            Book(libid: $0.libid, title: $0.title, authorIDs: [1], seriesID: nil, seriesNum: nil,
                 genreIDs: [], language: "ru", archiveIndex: $0.archive, size: 0, dateAdded: nil)
        }
        return Library(inpxHash: Data(count: 32), inpxVersion: "v", archives: ["present", "missing"],
                       authors: authors, series: [], genres: [], books: list)
    }

    private func run(_ lib: Library, items: [ExportItem]? = nil, root: URL? = nil) async -> ExportProgress {
        let plan = items ?? ExportPlanner.plan(libids: Set(lib.books.map(\.libid)), rootFolder: out,
                                               selectedAuthorID: nil, selectedSeriesID: nil, in: lib)
        let progress = ExportProgress()
        await ExportRunner.run(items: plan, exportRoot: root ?? out, archivesRoot: archives,
                               library: lib, progress: progress)
        return progress
    }

    @Test("книга с названием в 200 кириллических символов записывается")
    func longCyrillicTitleIsWritten() async throws {
        let title = String(repeating: "й", count: 200)
        let progress = await run(try library([(1, title, 0)]))
        #expect(progress.failed.isEmpty)
        #expect(progress.succeeded == [1])
        let files = try FileManager.default.contentsOfDirectory(
            at: out.appendingPathComponent("Толстой Лев"), includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(try Data(contentsOf: files[0]) == payload(1))
    }

    @Test("ошибка источника не прерывает выгрузку")
    func sourceErrorContinues() async throws {
        let progress = await run(try library([(1, "Есть", 0), (2, "Нет архива", 1), (3, "Нет в архиве", 0)],
                                             absent: [3]))
        #expect(progress.abortReason == nil)
        #expect(progress.done == 3)
        #expect(progress.succeeded == [1])
        #expect(progress.failed.map { $0.error } == ["Книга не найдена в архиве present.zip",
                                                     "Архив не найден — missing.zip"])
    }

    @Test("ошибка записи с непрерывающим кодом не прерывает выгрузку")
    func nonFatalWriteErrorContinues() async throws {
        let lib = try library([(1, "a", 0), (2, "b", 0)])
        let tooLong = out.appendingPathComponent(String(repeating: "x", count: 300) + ".fb2")
        let items = [ExportItem(book: lib.books[0], archiveURL: nil, destination: tooLong),
                     ExportItem(book: lib.books[1], archiveURL: nil, destination: out.appendingPathComponent("b.fb2"))]
        let progress = await run(lib, items: items)
        #expect(progress.abortReason == nil)
        #expect(progress.failed.map { $0.error } == ["Слишком длинное имя файла"])
        #expect(progress.succeeded == [2])
        #expect(progress.done == 2)
    }

    @Test("ошибка папки назначения прерывает выгрузку, остальные книги не трогаются",
          .enabled(if: getuid() != 0, "root пишет в папку только для чтения"))
    func destinationErrorAborts() async throws {
        let lib = try library([(1, "a", 0), (2, "b", 0), (3, "c", 0)])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: out.path)
        let progress = await run(lib)
        #expect(progress.abortReason == "Нет доступа к папке")
        #expect(progress.failed.count == 1)
        #expect(progress.failed.first?.title == "a")
        #expect(progress.failed.first?.error == "Нет доступа к папке")
        #expect(progress.succeeded.isEmpty)
        #expect(progress.done == 1)
        #expect(progress.total == 3)
    }

    @Test("недоступный корень выгрузки прерывает её до первой книги")
    func missingRootAborts() async throws {
        let lib = try library([(1, "a", 0)])
        let gone = dir.appendingPathComponent("gone", isDirectory: true)
        let items = ExportPlanner.plan(libids: [1], rootFolder: gone, selectedAuthorID: nil,
                                       selectedSeriesID: nil, in: lib)
        let progress = await run(lib, items: items, root: gone)
        #expect(progress.abortReason == "Диск недоступен")
        #expect(progress.succeeded.isEmpty)
        #expect(progress.done == 0)
        #expect(!FileManager.default.fileExists(atPath: gone.path))
    }
}

@Suite("ExportFailure")
struct ExportFailureTests {
    private let zip = URL(fileURLWithPath: "/lib/fb2-001.zip")

    private func posix(_ code: Int32) -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }

    @Test("ошибки источника — причина по-русски, выгрузка продолжается")
    func sourceReasons() {
        let cases: [(Error, String)] = [
            (ZipFB2Reader.ReaderError.archiveNotFound(zip), "Архив не найден — fb2-001.zip"),
            (ZipFB2Reader.ReaderError.archiveUnreadable(zip, underlying: posix(EIO)),
             "Не удалось прочитать архив fb2-001.zip"),
            (ZipFB2Reader.ReaderError.archiveCorrupt(zip, underlying: posix(EIO)), "Архив повреждён — fb2-001.zip"),
            (ZipFB2Reader.ReaderError.bookNotFoundInArchive(zip: zip, entryName: "1.fb2"),
             "Книга не найдена в архиве fb2-001.zip"),
            (ZipCentralDirectory.ZipError.truncated(zip), "Архив повреждён"),
            (posix(ENOSPC), "Не удалось прочитать архив"),
        ]
        for (error, reason) in cases {
            let failure = ExportFailure(error, stage: .source)
            #expect(failure.reason == reason)
            #expect(!failure.abortsExport)
        }
    }

    @Test("ошибки назначения: прерывающие коды",
          arguments: [(ENOSPC, "Нет места на диске"), (EDQUOT, "Нет места на диске"),
                      (EROFS, "Диск доступен только для чтения"), (EACCES, "Нет доступа к папке"),
                      (EPERM, "Нет доступа к папке"), (EIO, "Диск недоступен"), (ENXIO, "Диск недоступен"),
                      (ENODEV, "Диск недоступен"), (ENOENT, "Диск недоступен")])
    func fatalDestination(code: Int32, reason: String) {
        let failure = ExportFailure(posix(code), stage: .destination)
        #expect(failure.reason == reason)
        #expect(failure.abortsExport)
    }

    @Test("ошибки назначения: непрерывающие коды",
          arguments: [(ENAMETOOLONG, "Слишком длинное имя файла"), (EILSEQ, "Не удалось записать файл"),
                      (EINVAL, "Не удалось записать файл")])
    func nonFatalDestination(code: Int32, reason: String) {
        let failure = ExportFailure(posix(code), stage: .destination)
        #expect(failure.reason == reason)
        #expect(!failure.abortsExport)
    }

    @Test("POSIX-код достаётся из обёртки Cocoa")
    func cocoaWrapped() {
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                              userInfo: [NSUnderlyingErrorKey: posix(ENOSPC)])
        #expect(ExportFailure(wrapped, stage: .destination) == ExportFailure(reason: "Нет места на диске", abortsExport: true))
        let bare = CocoaError(.fileWriteOutOfSpace)
        #expect(ExportFailure(bare, stage: .destination).reason == "Нет места на диске")
        let unknown = NSError(domain: "x", code: 1)
        #expect(ExportFailure(unknown, stage: .destination) == ExportFailure(reason: "Не удалось записать файл", abortsExport: false))
    }
}
