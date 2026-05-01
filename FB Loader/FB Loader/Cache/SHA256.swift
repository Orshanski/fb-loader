import Foundation
import CryptoKit

enum SHA256 {
    static func hash(of data: Data) -> Data {
        Data(CryptoKit.SHA256.hash(data: data))
    }

    static func hash(ofFileAt url: URL) throws -> Data {
        let h = try url.withUnsafeFileSystemRepresentation { _ in
            // For files we expect (~36 MB INPX), reading whole into memory is fine.
            try Data(contentsOf: url)
        }
        return hash(of: h)
    }
}
