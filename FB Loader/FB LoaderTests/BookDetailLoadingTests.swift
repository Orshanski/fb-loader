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

    @Test("отмена ожидающей задачи доходит до фоновой работы")
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

@Suite("Отмена загрузки каталога")
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
}
