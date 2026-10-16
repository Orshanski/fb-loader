import Foundation

/// `nonisolated` so `load(inpxURL:)` runs off the main thread when called from MainActor;
/// under the MainActor default the heavy INPX parse would freeze the UI.
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

    /// `onProgress` fires from a background context, only on the rebuild path (cache hits skip it);
    /// the caller hops to MainActor itself.
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
