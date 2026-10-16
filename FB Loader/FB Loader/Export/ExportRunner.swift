import Foundation

enum ExportRunner {
    /// Runs on the main actor so `progress` can be mutated without hops.
    /// Heavy work (zip read + convert + file write) is one detached task per book — sequential to
    /// keep disk thrashing low and to match freeLib's behaviour (exportthread.cpp processes books one by one).
    @MainActor
    static func run(items: [ExportItem],
                    exportRoot: URL,
                    progress: ExportProgress,
                    converter: any ExportConverter = PassthroughConverter(),
                    onExported: @escaping @MainActor (Int32) -> Void = { _ in }) async {
        progress.total = items.count
        progress.done = 0
        progress.currentTitle = ""
        progress.cancelled = false
        progress.failed = []
        progress.abortReason = nil
        progress.succeeded = []

        // Отключённый том даёт EACCES от /Volumes, а не ENOENT — проверяем корень заранее.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: exportRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            progress.abortReason = "Диск недоступен"
            return
        }

        for item in items {
            if progress.cancelled { return }
            progress.currentTitle = item.book.title

            let work = Task.detached(priority: .utility) { () throws -> ExportFailure? in
                try await process(item, converter: converter)
            }
            // «Отмена» — флаг на main actor; в отменяемую задачу книги его переносит опрос.
            let watcher = Task { @MainActor in
                while !Task.isCancelled {
                    if progress.cancelled { work.cancel(); return }
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            let result = await work.result
            watcher.cancel()

            let failure: ExportFailure?
            switch result {
            case .success(let value): failure = value
            case .failure: return
            }

            if let failure {
                progress.failed.append((item.book.title, failure.reason))
                if failure.abortsExport { progress.abortReason = failure.reason }
            } else {
                progress.succeeded.insert(item.book.libid)
                onExported(item.book.libid)
            }
            progress.done += 1
            if progress.abortReason != nil { return }
        }
    }

    /// Бросает `CancellationError`, если книгу отменили; прочие ошибки возвращает как `ExportFailure`.
    private nonisolated static func process(_ item: ExportItem,
                                            converter: any ExportConverter) async throws -> ExportFailure? {
        let fb2: Data
        do {
            fb2 = try ZipFB2Reader.readFB2(entryName: item.book.archiveEntryName, archiveURL: item.archiveURL)
        } catch {
            return ExportFailure(error, stage: .source)
        }
        try Task.checkCancellation()
        let converted: Data
        do {
            converted = try await converter.convert(fb2, book: item.book)
        } catch {
            // Конвертер, прерванный отменой, может бросить любую ошибку.
            try Task.checkCancellation()
            return ExportFailure(error, stage: .conversion)
        }
        try Task.checkCancellation()
        do {
            try FileManager.default.createDirectory(
                at: item.destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try converted.write(to: item.destination, options: .atomic)
            return nil
        } catch {
            return ExportFailure(error, stage: .destination)
        }
    }
}
