import Foundation

nonisolated struct ExportFormat: Hashable, Sendable {
    let fileExtension: String
    static let fb2 = ExportFormat(fileExtension: "fb2")
}

nonisolated protocol ExportConverter: Sendable {
    /// Обязан реагировать на отмену задачи (прервать работу, в т. ч. внешний процесс).
    @concurrent func convert(_ fb2: Data, book: Book) async throws -> Data
}

nonisolated struct PassthroughConverter: ExportConverter {
    @concurrent func convert(_ fb2: Data, book: Book) async throws -> Data { fb2 }
}

nonisolated struct ExportConversionError: Error, Equatable {
    let reason: String
    /// Повторится на каждой книге (например, конвертер не установлен).
    let abortsExport: Bool
}

nonisolated enum ExportConverters {
    static func make(_ format: ExportFormat) -> any ExportConverter {
        precondition(format == .fb2, "UI не должен запрашивать формат без конвертера")
        return PassthroughConverter()
    }
}
