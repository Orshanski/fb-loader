import Foundation

enum ExportRunner {
    /// One detached task per book, sequentially: keeps disk thrashing low and matches freeLib (exportthread.cpp).
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
            progress.currentWork = work
            let result = await work.result
            progress.currentWork = nil

            let failure: ExportFailure?
            switch result {
            case .success(let value): failure = value
            case .failure: return
            }

            if let failure {
                progress.failed.append((item.book.title, failure.reason))
                if failure.abortsExport { progress.abortReason = failure.reason }
            } else {
                onExported(item.book.libid)
            }
            progress.done += 1
            if progress.abortReason != nil { return }
        }
    }

    /// Бросает `CancellationError`, если книгу отменили; прочие ошибки возвращает как `ExportFailure`.
    @concurrent private static func process(_ item: ExportItem,
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
