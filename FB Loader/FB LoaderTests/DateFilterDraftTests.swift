import Foundation
import Testing
@testable import FB_Loader

/// Календарь с фиксированным поясом — тесты не зависят от машины.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite("DateFilterDraft")
struct DateFilterDraftTests {
    private func draft(from: Date = at(2000, 1, 1),
                       to: Date = at(2026, 10, 15, 14, 30)) -> DateFilterDraft {
        DateFilterDraft(from: from, to: to, calendar: cal)
    }

    @Test("поля не тронуты — «Найти» неактивна")
    func untouched() {
        #expect(!draft().canApply)
    }

    @Test("исходное «по» с часами, поле — полночь того же дня")
    func initialWithTimeVsMidnight() {
        var d = draft()
        d.to = at(2026, 10, 15)
        #expect(!d.canApply)
    }

    @Test("тот же день с другим временем — не правка")
    func sameDayDifferentTime() {
        var d = draft(to: at(2026, 10, 15))
        d.to = at(2026, 10, 15, 23, 59)
        #expect(!d.canApply)
    }

    @Test("изменено «с»")
    func fromChanged() {
        var d = draft()
        d.from = at(2000, 1, 2)
        #expect(d.canApply)
    }

    @Test("изменено «по»")
    func toChanged() {
        var d = draft()
        d.to = at(2026, 10, 14)
        #expect(d.canApply)
    }

    @Test("изменены обе границы")
    func bothChanged() {
        var d = draft()
        d.from = at(2013, 3, 1)
        d.to = at(2015, 6, 30)
        #expect(d.canApply)
    }

    @Test("открыт с применённым фильтром — сравнение с ним, а не с умолчаниями")
    func openedWithAppliedFilter() {
        var d = draft(from: at(2013, 3, 1), to: at(2015, 6, 30))
        #expect(!d.canApply)
        d.to = at(2015, 7, 1)
        #expect(d.canApply)
    }

    @Test("изменено и возвращено — снова неактивна")
    func changedAndReverted() {
        var d = draft()
        d.from = at(2010, 5, 5)
        d.from = at(2000, 1, 1)
        #expect(!d.canApply)
    }

    @Test("applied приводит обе границы к полуночи")
    func appliedNormalized() {
        var d = draft()
        d.from = at(2013, 3, 1, 9, 15)
        #expect(d.applied == DateRangeFilter(from: at(2013, 3, 1), to: at(2026, 10, 15)))
    }
}
