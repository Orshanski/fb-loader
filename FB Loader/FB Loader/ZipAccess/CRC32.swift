import Foundation
import zlib

/// Через zlib: аппаратно ускорена, а считать приходится и весь INPX.
nonisolated enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> UInt32 in
            guard let base = buf.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            var crc = crc32(0, nil, 0)
            var offset = 0
            while offset < buf.count {
                let n = min(buf.count - offset, Int(UInt32.max))
                crc = crc32(crc, base + offset, uInt(n))
                offset += n
            }
            return UInt32(crc)
        }
    }
}
