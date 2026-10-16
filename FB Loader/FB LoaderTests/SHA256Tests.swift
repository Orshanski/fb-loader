import Testing
import Foundation
@testable import FB_Loader

@Suite("SHA256")
struct SHA256Tests {
    @Test("hashes empty data to known value")
    func empty() {
        let h = SHA256.hash(of: Data())
        let hex = h.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("hashes 'abc'")
    func abc() {
        let h = SHA256.hash(of: Data("abc".utf8))
        let hex = h.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("hashes a file at a URL")
    func file() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sha256-test-\(UUID()).bin")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let h = try SHA256.hash(ofFileAt: url)
        let hex = h.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
