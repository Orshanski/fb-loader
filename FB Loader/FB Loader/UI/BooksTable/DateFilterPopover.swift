import SwiftUI

/// Содержимое поповера, который открывается кликом по заголовку колонки
/// «Дата». Правка полей ни на что не влияет до нажатия «Найти».
///
/// Календарь разворачивается внутри этого же окна, а не отдельным поповером
/// поверх него: вложенный поповер на macOS рисуется над родительским и
/// накрывает кнопки.
struct DateFilterPopover: View {
    let current: DateRangeFilter?
    /// `nil` — снять фильтр. Вызывающая сторона закрывает поповер.
    let onApply: (DateRangeFilter?) -> Void

    private enum Bound { case from, to }

    @State private var from: Date
    @State private var to: Date
    @State private var editing: Bound?

    init(current: DateRangeFilter?, onApply: @escaping (DateRangeFilter?) -> Void) {
        self.current = current
        self.onApply = onApply
        _from = State(initialValue: current?.from ?? Self.defaultFrom)
        _to = State(initialValue: current?.to ?? Date())
    }

    private static let defaultFrom: Date = {
        var dc = DateComponents()
        dc.year = 2000; dc.month = 1; dc.day = 1
        return Calendar.current.date(from: dc) ?? Date()
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("с", date: from, bound: .from)
            field("по", date: to, bound: .to)

            if let editing {
                Divider()
                calendar(for: editing)
            }

            Divider()
            HStack {
                Button("Сбросить") { onApply(nil) }
                Spacer()
                Button("Найти") { onApply(applied()) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func field(_ label: String, date: Date, bound: Bound) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            Button {
                editing = (editing == bound) ? nil : bound
            } label: {
                HStack(spacing: 6) {
                    Text(DateFormat.dayMonthYear.string(from: date))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Image(systemName: "calendar")
                        .foregroundStyle(editing == bound ? AnyShapeStyle(.tint)
                                                          : AnyShapeStyle(.secondary))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .textBackgroundColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(editing == bound ? Color.accentColor
                                                 : Color.secondary.opacity(0.35),
                                lineWidth: editing == bound ? 1 : 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13))
    }

    @ViewBuilder
    private func calendar(for bound: Bound) -> some View {
        HStack {
            Spacer(minLength: 0)
            MonthCalendar(selection: bound == .from ? $from : $to) {
                editing = nil
            }
            Spacer(minLength: 0)
        }
    }

    /// Часы обнуляются так же, как у книг при импорте, — дальше сравниваются
    /// две полуночи.
    private func applied() -> DateRangeFilter {
        let cal = Calendar.current
        return DateRangeFilter(from: cal.startOfDay(for: from),
                               to: cal.startOfDay(for: to))
    }
}
