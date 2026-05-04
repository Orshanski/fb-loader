import Testing
import Foundation
@testable import FB_Loader

@Suite("UserPaths")
struct UserPathsTests {
    @Test("read-then-write round-trip")
    func roundTrip() {
        let suite = UserDefaults(suiteName: "FB_Loader.test.\(UUID())")!
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

    @Test("setting nil clears a previously stored path")
    func clearViaNil() {
        let suite = UserDefaults(suiteName: "FB_Loader.test.\(UUID())")!
        let paths = UserPaths(defaults: suite)
        paths.inpxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("x.inpx")
        #expect(paths.inpxURL != nil)
        paths.inpxURL = nil
        #expect(paths.inpxURL == nil)
    }
}
