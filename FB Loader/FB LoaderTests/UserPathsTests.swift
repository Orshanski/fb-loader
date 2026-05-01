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
        let inpx = URL(fileURLWithPath: "/tmp/test.inpx")
        let arch = URL(fileURLWithPath: "/Volumes/disk")
        let exp = URL(fileURLWithPath: "/Users/me/Downloads")
        paths.inpxURL = inpx
        paths.archivesDirectoryURL = arch
        paths.lastExportDirectoryURL = exp
        #expect(paths.inpxURL == inpx)
        #expect(paths.archivesDirectoryURL == arch)
        #expect(paths.lastExportDirectoryURL == exp)
    }
}
