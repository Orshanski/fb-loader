import Foundation

enum LibraryLoader {
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
    static func load(inpxURL: URL) async throws -> Library {
        let appSupport = try appSupportRoot()
        let store = LibraryCacheStore(applicationSupportRoot: appSupport)
        let genres = try GenreDictionary.loadFromBundle()
        return try store.loadOrRebuild(inpxURL: inpxURL) {
            try INPXImporter.import_(inpxURL: inpxURL, genres: genres)
        }
    }
}
