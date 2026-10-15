import Foundation

/// Поля поповера фильтра по дате. «Найти» активна, только когда поля
/// разошлись по дню с тем, что стояло в них при открытии поповера.
nonisolated struct DateFilterDraft: Equatable, Sendable {
    /// Поля при открытии, приведённые к полуночи.
    let initial: DateRangeFilter
    var from: Date
    var to: Date
    private let calendar: Calendar

    init(from: Date, to: Date, calendar: Calendar = .current) {
        self.from = from
        self.to = to
        self.calendar = calendar
        initial = Self.days(from: from, to: to, calendar: calendar)
    }

    /// Часы обнуляются так же, как у книг при импорте, — дальше
    /// сравниваются две полуночи.
    var applied: DateRangeFilter {
        Self.days(from: from, to: to, calendar: calendar)
    }

    var canApply: Bool { applied != initial }

    private static func days(from: Date, to: Date, calendar: Calendar) -> DateRangeFilter {
        DateRangeFilter(from: calendar.startOfDay(for: from),
                        to: calendar.startOfDay(for: to))
    }
}
