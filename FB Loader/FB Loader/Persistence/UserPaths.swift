import Foundation

/// The only state persisted between app launches:
/// - inpxURL: path to the INPX file
/// - archivesDirectoryURL: directory containing the .zip archives
/// - lastExportDirectoryURL: pre-fill for the next export-folder dialog
///
/// All other UI state (window size, selection, filters) is intentionally NOT persisted.
///
/// `Sendable` is required by Swift 6 for the `static let shared` global. The class
/// only stores a `let defaults: UserDefaults` (itself Sendable), so the conformance
/// is clean — there's no shared mutable in-process state to worry about.
final class UserPaths: Sendable {
    /// The single shared instance used by AppState and SettingsView.
    /// Production code uses `.shared`; tests instantiate with a custom UserDefaults suite.
    static let shared = UserPaths()

    private let defaults: UserDefaults
    private enum Keys: String {
        case inpx = "fbloader.inpx"
        case archives = "fbloader.archives"
        case lastExport = "fbloader.lastExport"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var inpxURL: URL? {
        get { url(for: .inpx) }
        set { set(newValue, for: .inpx) }
    }
    var archivesDirectoryURL: URL? {
        get { url(for: .archives) }
        set { set(newValue, for: .archives) }
    }
    var lastExportDirectoryURL: URL? {
        get { url(for: .lastExport) }
        set { set(newValue, for: .lastExport) }
    }

    private func url(for key: Keys) -> URL? {
        // `defaults.set(nil, forKey:)` removes the key, so `string(forKey:)`
        // never returns an empty string here — only nil or a real path.
        guard let s = defaults.string(forKey: key.rawValue) else { return nil }
        return URL(fileURLWithPath: s)
    }
    private func set(_ url: URL?, for key: Keys) {
        defaults.set(url?.path, forKey: key.rawValue)
    }
}
