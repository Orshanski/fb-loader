import SwiftUI

/// Сетка месяца с выбором дня.
///
/// Своя, а не `DatePicker(.graphical)`: системная выглядит как контрол из
/// девяностых и не поддаётся стилизации.
struct MonthCalendar: View {
    @Binding var selection: Date

    /// Месяц, который сейчас показан. Листается стрелками независимо от
    /// выбранного дня.
    @State private var visibleMonth: Date

    private let cellSize: CGFloat = 30
    private let onPick: () -> Void

    init(selection: Binding<Date>, onPick: @escaping () -> Void = {}) {
        _selection = selection
        _visibleMonth = State(initialValue: Self.cal.startOfMonth(selection.wrappedValue))
        self.onPick = onPick
    }

    /// Понедельник первым, русские названия — интерфейс приложения русский.
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = 2
        return c
    }()

    private static let monthTitle: DateFormatter = {
        let f = DateFormatter()
        f.calendar = cal
        f.locale = cal.locale
        f.dateFormat = "LLLL"
        return f
    }()

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayRow
            grid
            todayButton
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 4) {
            stepButton("chevron.left", months: -1)
            HStack(spacing: 6) {
                monthMenu
                yearMenu
            }
            .frame(maxWidth: .infinity)
            stepButton("chevron.right", months: 1)
        }
    }

    private var monthMenu: some View {
        dropdown(title: Self.monthTitle.string(from: visibleMonth).capitalized) {
            ForEach(1...12, id: \.self) { m in
                Button(Self.monthName(m)) { jump(toMonth: m) }
            }
        }
    }

    /// Год меню, а не стрелками: пролистывать из 2026 в 2009 — двести
    /// с лишним кликов.
    private var yearMenu: some View {
        dropdown(title: String(visibleYear)) {
            ForEach(selectableYears.reversed(), id: \.self) { y in
                Button(String(y)) { jump(toYear: y) }
            }
        }
    }

    /// Общий вид для обоих меню: подпись, своя стрелка справа, системный
    /// индикатор спрятан — иначе он рисуется слева и читается как стрелка
    /// соседнего элемента.
    private func dropdown<Content: View>(title: String,
                                         @ViewBuilder items: () -> Content) -> some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var visibleYear: Int { Self.cal.component(.year, from: visibleMonth) }

    private static func monthName(_ month: Int) -> String {
        let symbols = cal.standaloneMonthSymbols
        guard (1...symbols.count).contains(month) else { return "" }
        return symbols[month - 1].capitalized
    }

    /// От начала каталога Флибусты до текущего года.
    private var selectableYears: [Int] {
        let now = Self.cal.component(.year, from: Date())
        return Array(2000...max(2000, now))
    }

    private func jump(toYear year: Int) {
        var dc = Self.cal.dateComponents([.year, .month], from: visibleMonth)
        dc.year = year
        if let next = Self.cal.date(from: dc) { visibleMonth = next }
    }

    private func jump(toMonth month: Int) {
        var dc = Self.cal.dateComponents([.year, .month], from: visibleMonth)
        dc.month = month
        if let next = Self.cal.date(from: dc) { visibleMonth = next }
    }

    private var todayButton: some View {
        Button("Сегодня") {
            let today = Date()
            selection = today
            visibleMonth = Self.cal.startOfMonth(today)
            onPick()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.tint)
        .padding(.top, 2)
    }

    private func stepButton(_ icon: String, months: Int) -> some View {
        Button {
            if let next = Self.cal.date(byAdding: .month, value: months, to: visibleMonth) {
                visibleMonth = next
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Дни недели

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            // Ключ по позиции, а не по тексту: подписи повторяются
            // («пн»/«пт» дают одну букву «П» в very-short варианте, да и
            // двухбуквенные не гарантируют уникальности в любой локали).
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: cellSize)
            }
        }
    }

    /// Двухбуквенные подписи: однобуквенные в русской локали неразличимы —
    /// «П» это и понедельник, и пятница.
    /// Символы начинаются с воскресенья, переставляем под `firstWeekday`.
    private var weekdaySymbols: [String] {
        let symbols = Self.cal.shortStandaloneWeekdaySymbols
        let shift = Self.cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    // MARK: - Сетка

    private var grid: some View {
        VStack(spacing: 2) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        cell(day)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: Date?) -> some View {
        if let day {
            let selected = Self.cal.isDate(day, inSameDayAs: selection)
            let today = Self.cal.isDateInToday(day)
            Button {
                selection = day
                onPick()
            } label: {
                Text("\(Self.cal.component(.day, from: day))")
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(selected ? AnyShapeStyle(.white)
                                     : today ? AnyShapeStyle(.tint)
                                             : AnyShapeStyle(.primary))
                    .frame(width: cellSize, height: cellSize)
                    .background {
                        if selected {
                            Circle().fill(Color.accentColor)
                        } else if today {
                            Circle().stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: cellSize, height: cellSize)
        }
    }

    /// Дни видимого месяца, разложенные по неделям. `nil` — пустая клетка до
    /// первого и после последнего числа.
    private var weeks: [[Date?]] {
        let cal = Self.cal
        let first = cal.startOfMonth(visibleMonth)
        guard let range = cal.range(of: .day, in: .month, for: first) else { return [] }

        let weekdayOfFirst = cal.component(.weekday, from: first)
        let leading = (weekdayOfFirst - cal.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            cells.append(cal.date(byAdding: .day, value: offset, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }
}

private extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
