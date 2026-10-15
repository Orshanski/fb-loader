import Foundation

enum ExportRunner {
    /// Runs entirely on the main actor so `progress` can be mutated without hops.
    /// Heavy I/O (zip read + file write) is dispatched off-main via `Task.detached`.
    /// One detached task per book — sequential to keep disk/network thrashing low and
    /// to match freeLib's behaviour (exportthread.cpp processes books one by one).
    @MainActor
    static func run(items: [ExportItem],
                    archivesRoot: URL,
                    library: Library,
                    progress: ExportProgress) async {
        progress.total = items.count
        progress.done = 0
        progress.currentTitle = ""
        progress.cancelled = false
        progress.failed = []
        progress.succeeded = []

        for item in items {
            if progress.cancelled { return }
            progress.currentTitle = item.book.title

            let book = item.book
            let dest = item.destination
            let archives = archivesRoot
            let archiveName = library.archives[Int(book.archiveIndex)] + ".zip"

            // Off-main: open zip, extract bytes, write to disk.
            // Returns nil on success, or the error message on failure.
            let errorMessage: String? = await Task.detached(priority: .utility) { () -> String? in
                let archiveURL = archives.appendingPathComponent(archiveName)
                do {
                    let data = try ZipFB2Reader.readFB2(entryName: book.archiveEntryName, archiveURL: archiveURL)
                    try FileManager.default.createDirectory(
                        at: dest.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    try data.write(to: dest, options: .atomic)
                    return nil
                } catch {
                    return "\(error)"
                }
            }.value

            // Invariant: succeeded/failed обновляются ДО `done += 1`,
            // чтобы `.onChange(of: progress.done)` в родительской вьюхе
            // видел консистентное состояние при срабатывании.
            if let msg = errorMessage {
                progress.failed.append((book.title, msg))
            } else {
                progress.succeeded.insert(book.libid)
            }
            progress.done += 1
        }
    }
}
