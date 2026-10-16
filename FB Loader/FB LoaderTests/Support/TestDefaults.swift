import Foundation

/// Suite с абсолютным путём пишет plist в свой временный каталог, а не в ~/Library/Preferences:
/// удаление домена оставляет там пустой plist, который cfprefsd создаёт асинхронно.
final class TestDefaults {
    let defaults: UserDefaults
    private let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FB_Loader.test.\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: directory.appendingPathComponent("defaults").path)!
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: directory.appendingPathComponent("defaults").path)
        try? FileManager.default.removeItem(at: directory)
    }
}

func withTestDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    let box = TestDefaults()
    defer { box.cleanUp() }
    return try body(box.defaults)
}
