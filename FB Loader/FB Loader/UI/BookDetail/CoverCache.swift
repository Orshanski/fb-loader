import Foundation
import AppKit

/// Disk-backed jpg cache for FB2 cover images at
/// `~/Library/Caches/<bundleID>/covers/<libid>.jpg`. Caller extracts cover
/// bytes from an already-parsed `FB2BookInfo` and calls `store(_:for:)`;
/// next visit hits `cachedImage(for:)` directly.
///
/// `nonisolated final class` + `Sendable`: единственное изменяемое состояние — суммарный размер
/// и вытеснение — спрятано в `Accounting` под одной блокировкой, `cacheDir` и лимит неизменны;
/// чтение готового файла безопасно на уровне ОС.
nonisolated final class CoverCache: Sendable {
    static let defaultLimitBytes = 200 * 1024 * 1024

    static let shared: CoverCache? = {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .cachesDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "FB-Loader",
                                              isDirectory: true)
            .appendingPathComponent("covers", isDirectory: true)
        return try? CoverCache(directory: dir)
    }()

    private let cacheDir: URL
    private let limitBytes: Int
    private let accounting = Accounting()

    /// Запись, подсчёт размера и вытеснение идут под одной блокировкой: параллельные `store` не
    /// считают размер дважды и не удаляют файлы друг у друга.
    private final class Accounting: @unchecked Sendable {
        let lock = NSLock()
        /// nil до первого обхода каталога; дальше размер ведётся приращениями, без обхода на каждой записи.
        var total: Int?
    }

    init(directory: URL, limitBytes: Int = CoverCache.defaultLimitBytes) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.cacheDir = directory
        self.limitBytes = limitBytes
    }

    /// Disk-cached cover, if previously stored. Caller checks this first; on
    /// miss, the caller is responsible for extracting cover bytes from an
    /// already-parsed `FB2BookInfo` and calling `store(_:for:)` to persist.
    func cachedImage(for book: Book) -> NSImage? {
        let url = cacheURL(for: book)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        // Обновляем дату изменения при попадании: вытеснение по ней становится LRU (atime на APFS ненадёжен).
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return NSImage(contentsOf: url)
    }

    /// Writes cover bytes to the disk cache and returns an NSImage for them. Вызывать вне main actor.
    func store(_ coverBytes: Data, for book: Book) -> NSImage? {
        let url = cacheURL(for: book)
        accounting.lock.withLock {
            let fm = FileManager.default
            let oldSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard (try? coverBytes.write(to: url, options: .atomic)) != nil else { return }
            if let total = accounting.total {
                accounting.total = total - oldSize + coverBytes.count
            } else {
                accounting.total = scan(fm).reduce(0) { $0 + $1.size }
            }
            if let total = accounting.total, total > limitBytes { trim(keeping: url, fm) }
        }
        return NSImage(data: coverBytes)
    }

    private typealias Entry = (url: URL, size: Int, date: Date)

    /// Только готовые `.jpg`: временные файлы атомарной записи (в том числе чужого процесса) не учитываются и не удаляются.
    private func scan(_ fm: FileManager) -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: keys) else { return [] }
        return urls.compactMap { u in
            guard u.pathExtension == "jpg",
                  let v = try? u.resourceValues(forKeys: Set(keys)), let size = v.fileSize else { return nil }
            return (u, size, v.contentModificationDate ?? .distantPast)
        }
    }

    /// Удаляет самые давно использованные файлы, пока размер не опустится до 90% лимита:
    /// запас, чтобы следующая же запись не запускала вытеснение снова. Вызывать под блокировкой.
    private func trim(keeping keep: URL, _ fm: FileManager) {
        var files = scan(fm)
        var total = files.reduce(0) { $0 + $1.size }
        let target = limitBytes / 10 * 9
        files.sort { $0.date < $1.date }
        for f in files where total > target {
            if f.url.standardizedFileURL == keep.standardizedFileURL { continue }
            if (try? fm.removeItem(at: f.url)) != nil { total -= f.size }
        }
        accounting.total = total
    }

    private func cacheURL(for book: Book) -> URL {
        cacheDir.appendingPathComponent("\(book.libid).jpg")
    }
}
