import Foundation

/// `nonisolated` so `load(inpxURL:)` can be called from MainActor (e.g. SwiftUI's
/// `.task`) and actually run on a background cooperative thread instead of
/// blocking the main thread for the entire INPX import (~36 MB, 700k records).
/// Project default isolation is MainActor; without this the heavy I/O+parse
/// chain stays main-bound and freezes the UI.
nonisolated enum LibraryLoader {
    static func cacheURL() throws -> URL {
        LibraryCacheStore.cacheURL(in: try appSupportRoot())
    }

    static func appSupportRoot() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "FB-Loader",
                                              isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Load library: from cache if hash matches, else reparse INPX.
    /// Heavy — should be called from a background Task.
    /// `onProgress` is called from a background context every N parsed books
    /// (only on the rebuild path; cache hits skip it). The caller is responsible
    /// for hopping to MainActor before mutating UI state.
    static func load(
        inpxURL: URL,
        forceRebuild: Bool = false,
        onStatus: (@Sendable (String) -> Void)? = nil,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> Library {
        let appSupport = try appSupportRoot()
        let store = LibraryCacheStore(applicationSupportRoot: appSupport)
        let genres = try GenreDictionary.loadFromBundle()
        onStatus?("Чтение кэша каталога…")
        return try store.loadOrRebuild(
            inpxURL: inpxURL,
            sourceKey: LibraryCacheStore.sourceKey(genres: genres),
            forceRebuild: forceRebuild,
            onStatus: onStatus
        ) { inpxHash in
            onStatus?("Кэш не найден или устарел — пересборка из INPX")
            return try INPXImporter.parse(
                inpxURL: inpxURL,
                inpxHash: inpxHash,
                genres: genres,
                onStatus: onStatus,
                onProgress: onProgress)
        }
    }
}
