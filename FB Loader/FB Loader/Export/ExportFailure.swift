import Foundation

nonisolated struct ExportFailure: Equatable, Sendable {
    enum Stage { case source, destination }

    let reason: String
    /// Ошибка папки назначения повторится на каждой следующей книге.
    let abortsExport: Bool

    init(reason: String, abortsExport: Bool) {
        self.reason = reason
        self.abortsExport = abortsExport
    }

    init(_ error: Error, stage: Stage) {
        switch stage {
        case .source:
            self.init(reason: Self.sourceReason(error), abortsExport: false)
        case .destination:
            switch Self.posixCode(of: error) {
            case ENOSPC, EDQUOT:
                self.init(reason: "Нет места на диске", abortsExport: true)
            case EROFS:
                self.init(reason: "Диск доступен только для чтения", abortsExport: true)
            case EACCES, EPERM:
                self.init(reason: "Нет доступа к папке", abortsExport: true)
            case EIO, ENXIO, ENODEV, ENOENT:
                self.init(reason: "Диск недоступен", abortsExport: true)
            case ENAMETOOLONG:
                self.init(reason: "Слишком длинное имя файла", abortsExport: false)
            default:
                self.init(reason: "Не удалось записать файл", abortsExport: false)
            }
        }
    }

    private static func sourceReason(_ error: Error) -> String {
        switch error {
        case ZipFB2Reader.ReaderError.archiveNotFound(let url):
            "Архив не найден: \(url.lastPathComponent)"
        case ZipFB2Reader.ReaderError.archiveUnreadable(let url, _):
            "Не удалось прочитать архив \(url.lastPathComponent)"
        case ZipFB2Reader.ReaderError.archiveCorrupt(let url, _):
            "Архив повреждён: \(url.lastPathComponent)"
        case ZipFB2Reader.ReaderError.bookNotFoundInArchive(let url, _):
            "Книга не найдена в архиве \(url.lastPathComponent)"
        case is ZipCentralDirectory.ZipError:
            "Архив повреждён"
        default:
            "Не удалось прочитать архив"
        }
    }

    private static func posixCode(of error: Error) -> Int32? {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain { return Int32(ns.code) }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error,
           let code = posixCode(of: underlying) {
            return code
        }
        guard ns.domain == NSCocoaErrorDomain else { return nil }
        switch ns.code {
        case NSFileWriteOutOfSpaceError: return ENOSPC
        case NSFileWriteVolumeReadOnlyError: return EROFS
        case NSFileWriteNoPermissionError: return EACCES
        default: return nil
        }
    }
}
