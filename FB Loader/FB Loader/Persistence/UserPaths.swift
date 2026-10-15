import Foundation
import Observation

/// The only state persisted between app launches:
/// - inpxURL: path to the INPX file
/// - archivesDirectoryURL: directory containing the .zip archives
/// - lastExportDirectoryURL: pre-fill for the next export-folder dialog
///
/// All other UI state (window size, selection, filters) is intentionally NOT persisted.
///
/// Значения хранятся копией в свойствах, а не читаются из `UserDefaults` на лету:
/// `@Observable` отслеживает только хранимые свойства, иначе открытые
/// Настройки не видели бы смену пути.
@Observable
final class UserPaths {
    /// The single shared instance used by AppState and SettingsView.
    /// Production code uses `.shared`; tests instantiate with a custom UserDefaults suite.
    static let shared = UserPaths()

    @ObservationIgnored private let defaults: UserDefaults
    private enum Keys: String {
        case inpx = "fbloader.inpx"
        case archives = "fbloader.archives"
        case lastExport = "fbloader.lastExport"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        inpxURL = Self.url(for: .inpx, in: defaults)
        archivesDirectoryURL = Self.url(for: .archives, in: defaults)
        lastExportDirectoryURL = Self.url(for: .lastExport, in: defaults)
    }

    var inpxURL: URL? {
        didSet { store(inpxURL, for: .inpx) }
    }
    var archivesDirectoryURL: URL? {
        didSet { store(archivesDirectoryURL, for: .archives) }
    }
    var lastExportDirectoryURL: URL? {
        didSet { store(lastExportDirectoryURL, for: .lastExport) }
    }

    private static func url(for key: Keys, in defaults: UserDefaults) -> URL? {
        // `defaults.set(nil, forKey:)` removes the key, so `string(forKey:)`
        // never returns an empty string here — only nil or a real path.
        guard let s = defaults.string(forKey: key.rawValue) else { return nil }
        return URL(fileURLWithPath: s)
    }
    private func store(_ url: URL?, for key: Keys) {
        defaults.set(url?.path, forKey: key.rawValue)
    }
}
