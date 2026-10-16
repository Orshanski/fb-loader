import Foundation
import Observation

/// UI state (window size, selection, filters) is intentionally not persisted.
///
/// Значения хранятся копией в свойствах, а не читаются из `UserDefaults` на лету:
/// `@Observable` отслеживает только хранимые свойства, иначе открытые
/// Настройки не видели бы смену пути.
@Observable
final class UserPaths {
    /// Tests instantiate their own instance with a custom UserDefaults suite.
    static let shared = UserPaths()

    @ObservationIgnored private let defaults: UserDefaults
    /// @Observable гоняет didSet и при начальной загрузке в init: без флага он стёр бы сохранённые сведения о томе.
    @ObservationIgnored private var isLoaded = false
    private enum Keys: String {
        case inpx = "fbloader.inpx"
        case archives = "fbloader.archives"
        case lastExport = "fbloader.lastExport"
        case inpxVolume = "fbloader.inpxVolume"
        case archivesVolume = "fbloader.archivesVolume"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        inpxURL = Self.url(for: .inpx, in: defaults)
        archivesDirectoryURL = Self.url(for: .archives, in: defaults)
        lastExportDirectoryURL = Self.url(for: .lastExport, in: defaults)
        inpxVolume = Self.volume(for: .inpxVolume, in: defaults)
        archivesVolume = Self.volume(for: .archivesVolume, in: defaults)
        isLoaded = true
    }

    var inpxVolume: VolumeInfo? {
        didSet { storeVolume(inpxVolume, for: .inpxVolume) }
    }
    var archivesVolume: VolumeInfo? {
        didSet { storeVolume(archivesVolume, for: .archivesVolume) }
    }

    var inpxURL: URL? {
        didSet {
            store(inpxURL, for: .inpx)
            if isLoaded { inpxVolume = nil }
        }
    }
    var archivesDirectoryURL: URL? {
        didSet {
            store(archivesDirectoryURL, for: .archives)
            if isLoaded { archivesVolume = nil }
        }
    }

    /// Выбор пользователем. Сведения о томе определяются в фоне: зависший сетевой том не должен держать main.
    @discardableResult
    func setINPX(_ url: URL) -> Task<Void, Never> {
        inpxURL = url
        return Task {
            let v = await VolumeInfo.detectOffMain(url)
            if inpxURL == url, let v { inpxVolume = v }
        }
    }
    @discardableResult
    func setArchivesDirectory(_ url: URL) -> Task<Void, Never> {
        archivesDirectoryURL = url
        return Task {
            let v = await VolumeInfo.detectOffMain(url)
            if archivesDirectoryURL == url, let v { archivesVolume = v }
        }
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

    private static func volume(for key: Keys, in defaults: UserDefaults) -> VolumeInfo? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(VolumeInfo.self, from: data)
    }
    private func storeVolume(_ volume: VolumeInfo?, for key: Keys) {
        defaults.set(volume.flatMap { try? JSONEncoder().encode($0) }, forKey: key.rawValue)
    }
}
