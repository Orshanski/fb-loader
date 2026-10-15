import Foundation
import zlib

/// CRC-32 (IEEE 802.3) — та же, что в zip. Через системную zlib: она
/// аппаратно ускорена, а считать приходится и весь INPX при импорте.
nonisolated enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> UInt32 in
            guard let base = buf.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            var crc = crc32(0, nil, 0)
            var offset = 0
            // Длина у zlib — `uInt` (32 бита): режем на куски.
            while offset < buf.count {
                let n = min(buf.count - offset, Int(UInt32.max))
                crc = crc32(crc, base + offset, uInt(n))
                offset += n
            }
            return UInt32(crc)
        }
    }
}
