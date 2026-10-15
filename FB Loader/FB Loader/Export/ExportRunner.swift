import Foundation

enum ExportRunner {
    /// Runs entirely on the main actor so `progress` can be mutated without hops.
    /// Heavy I/O (zip read + file write) is dispatched off-main via `Task.detached`.
    /// One detached task per book — sequential to keep disk/network thrashing low and
    /// to match freeLib's behaviour (exportthread.cpp processes books one by one).
    @MainActor
    static func run(items: [ExportItem],
                    exportRoot: URL,
                    archivesRoot: URL,
                    library: Library,
                    progress: ExportProgress) async {
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

            let book = item.book
            let dest = item.destination
            let archives = archivesRoot
            let archiveName = library.archives[Int(book.archiveIndex)] + ".zip"

            // Off-main: open zip, extract bytes, write to disk.
            let failure: ExportFailure? = await Task.detached(priority: .utility) { () -> ExportFailure? in
                let archiveURL = archives.appendingPathComponent(archiveName)
                let data: Data
                do {
                    data = try ZipFB2Reader.readFB2(entryName: book.archiveEntryName, archiveURL: archiveURL)
                } catch {
                    return ExportFailure(error, stage: .source)
                }
                do {
                    try FileManager.default.createDirectory(
                        at: dest.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    try data.write(to: dest, options: .atomic)
                    return nil
                } catch {
                    return ExportFailure(error, stage: .destination)
                }
            }.value

            // Invariant: succeeded/failed/abortReason обновляются ДО `done += 1`,
            // чтобы `.onChange(of: progress.done)` в родительской вьюхе
            // видел консистентное состояние при срабатывании.
            if let failure {
                progress.failed.append((book.title, failure.reason))
                if failure.abortsExport { progress.abortReason = failure.reason }
            } else {
                progress.succeeded.insert(book.libid)
            }
            progress.done += 1
            if progress.abortReason != nil { return }
        }
    }
}
