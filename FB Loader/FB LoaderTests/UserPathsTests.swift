import Testing
import Foundation
@testable import FB_Loader

@Suite("UserPaths")
@MainActor
struct UserPathsTests {
    @Test("read-then-write round-trip")
    func roundTrip() {
        withTestDefaults { suite in
            let paths = UserPaths(defaults: suite)
            #expect(paths.inpxURL == nil)
            #expect(paths.archivesDirectoryURL == nil)
            #expect(paths.lastExportDirectoryURL == nil)
            let tmp = FileManager.default.temporaryDirectory
            let inpx = tmp.appendingPathComponent("test.inpx")
            let arch = tmp.appendingPathComponent("archives")
            let exp = tmp.appendingPathComponent("exports")
            paths.inpxURL = inpx
            paths.archivesDirectoryURL = arch
            paths.lastExportDirectoryURL = exp
            #expect(paths.inpxURL == inpx)
            #expect(paths.archivesDirectoryURL == arch)
            #expect(paths.lastExportDirectoryURL == exp)
        }
    }

    @Test("setting nil clears a previously stored path")
    func clearViaNil() {
        withTestDefaults { suite in
            let paths = UserPaths(defaults: suite)
            paths.inpxURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("x.inpx")
            #expect(paths.inpxURL != nil)
            paths.inpxURL = nil
            #expect(paths.inpxURL == nil)
        }
    }

    @Test("значения переживают новый экземпляр")
    func persistsAcrossInstances() {
        withTestDefaults { suite in
            let inpx = FileManager.default.temporaryDirectory.appendingPathComponent("p.inpx")
            UserPaths(defaults: suite).inpxURL = inpx
            #expect(UserPaths(defaults: suite).inpxURL == inpx)
        }
    }

    @Test("смена пути замечается наблюдателем SwiftUI")
    func changeIsObservable() {
        withTestDefaults { suite in
            let paths = UserPaths(defaults: suite)
            let changed = Flag()
            withObservationTracking {
                _ = paths.archivesDirectoryURL
            } onChange: {
                changed.value = true
            }

            paths.archivesDirectoryURL = FileManager.default.temporaryDirectory

            #expect(changed.value)
        }
    }

    private final class Flag: @unchecked Sendable { var value = false }
}

@Suite("UserPaths: сведения о томе")
@MainActor
struct UserPathsVolumeTests {
    private let info = VolumeInfo(name: "flibusta", isNetwork: true,
                                  remountURL: URL(string: "smb://alexey@nas._smb._tcp.local/flibusta"))

    @Test("сведения о томе хранятся отдельно для INPX и папки архивов и переживают перезапуск")
    func roundTrip() {
        withTestDefaults { suite in
            let paths = UserPaths(defaults: suite)
            #expect(paths.inpxVolume == nil)
            #expect(paths.archivesVolume == nil)
            paths.inpxVolume = info
            let other = VolumeInfo(name: "USB", isNetwork: false, remountURL: nil)
            paths.archivesVolume = other
            let reread = UserPaths(defaults: suite)
            #expect(reread.inpxVolume == info)
            #expect(reread.archivesVolume == other)
        }
    }

    @Test("nil стирает сведения")
    func clear() {
        withTestDefaults { suite in
            let paths = UserPaths(defaults: suite)
            paths.inpxVolume = info
            paths.inpxVolume = nil
            #expect(UserPaths(defaults: suite).inpxVolume == nil)
        }
    }

    @Test("выбор пути записывает сведения о его томе")
    func selectionRecordsVolume() {
        withTestDefaults { suite in
            let paths = UserPaths(defaults: suite)
            let dir = FileManager.default.temporaryDirectory
            let file = dir.appendingPathComponent("vol-\(UUID()).inpx")
            FileManager.default.createFile(atPath: file.path, contents: Data())
            defer { try? FileManager.default.removeItem(at: file) }
            paths.setINPX(file)
            paths.setArchivesDirectory(dir)
            #expect(paths.inpxURL == file)
            #expect(paths.inpxVolume != nil)
            #expect(paths.archivesVolume != nil)
        }
    }
}
