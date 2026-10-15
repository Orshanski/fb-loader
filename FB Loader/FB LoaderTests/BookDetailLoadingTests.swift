import Foundation
import Testing
@testable import FB_Loader

@Suite("Чтение книги для карточки")
struct BookDetailLoadingTests {
    private let zip = URL(fileURLWithPath: "/lib/fb2-001.zip")

    @Test("ошибка чтения — строка для карточки с русской причиной")
    func readFailureMessages() {
        let cases: [(Error, String)] = [
            (ZipFB2Reader.ReaderError.archiveNotFound(zip),
             "Не удалось прочитать книгу: архив не найден: fb2-001.zip"),
            (ZipFB2Reader.ReaderError.bookNotFoundInArchive(zip: zip, entryName: "1.fb2"),
             "Не удалось прочитать книгу: книга не найдена в архиве fb2-001.zip"),
            (FB2DescriptionParser.ParseError.malformed,
             "Не удалось прочитать книгу: файл книги повреждён"),
        ]
        for (error, message) in cases {
            #expect(BookReadFailure.message(for: error) == message)
        }
    }

    @Test("отмена ожидающей задачи доходит до фоновой работы", .timeLimit(.minutes(1)))
    func detachedWorkSeesCancellation() async {
        let started = AsyncStream<Void>.makeStream()
        let outer = Task {
            await runDetachedCancellable(priority: .utility) { () -> Bool in
                started.continuation.yield()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(5))
                }
                return true
            }
        }
        for await _ in started.stream { break }

        outer.cancel()

        #expect(await outer.value == true)
    }
}

@Suite("Отмена чтения архивов")
struct LibraryLoadCancellationTests {
    @Test("отменённая задача прерывает импорт INPX")
    func importerStopsWhenCancelled() async throws {
        let url = try #require(TestBundleAnchor.bundle.url(forResource: "tiny", withExtension: "inpx"))
        let dict = try GenreDictionary.loadFromBundle()
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try INPXImporter.parse(inpxURL: url, genres: dict)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("отменённая задача не распаковывает книгу из архива")
    func zipReaderStopsWhenCancelled() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let zip = dir.appendingPathComponent("lib.zip")
        try ZipBuilder(items: [.init(name: "1.fb2", payload: Data("<x/>".utf8))]).build().data.write(to: zip)

        #expect(try ZipFB2Reader.readFB2(entryName: "1.fb2", archiveURL: zip) == Data("<x/>".utf8))
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ZipFB2Reader.readFB2(entryName: "1.fb2", archiveURL: zip)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("отменённая загрузка не пишет кэш каталога")
    func cancelledLoadDoesNotSaveCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inpx = try #require(TestBundleAnchor.bundle.url(forResource: "tiny", withExtension: "inpx"))
        let dict = try GenreDictionary.loadFromBundle()
        let task = Task.detached {
            try LibraryCacheStore(applicationSupportRoot: root).loadOrRebuild(inpxURL: inpx, sourceKey: Data(repeating: 1, count: 32)) { hash in
                let lib = try INPXImporter.parse(inpxURL: inpx, inpxHash: hash, genres: dict)
                withUnsafeCurrentTask { $0?.cancel() }
                return lib
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: LibraryCacheStore.cacheURL(in: root).path))
    }
}
