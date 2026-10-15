import Foundation

nonisolated enum BookReadFailure {
    static func message(for error: Error) -> String {
        let reason = error is FB2DescriptionParser.ParseError
            ? "Файл книги повреждён"
            : ExportFailure(error, stage: .source).reason
        return "Не удалось прочитать книгу: " + reason.prefix(1).lowercased() + reason.dropFirst()
    }
}
