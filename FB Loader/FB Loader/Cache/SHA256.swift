import Foundation
import CryptoKit

nonisolated enum SHA256 {
    static func hash(of data: Data) -> Data {
        Data(CryptoKit.SHA256.hash(data: data))
    }

    static func hash(ofFileAt url: URL) throws -> Data {
        // For files we expect (~36 MB INPX), reading whole into memory is fine.
        try hash(of: Data(contentsOf: url))
    }
}
