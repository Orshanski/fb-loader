import Foundation
import CoreGraphics

/// Размер зоны главного окна, запоминаемый между запусками: пределы, ключ
/// в defaults и прижатие сохранённого значения к пределам.
nonisolated struct PaneDimension: Sendable {
    let key: String
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat

    static let sidebarWidth = PaneDimension(
        key: "fbloader.layout.sidebarWidth", min: 280, ideal: 300, max: 480)
    static let bookDetailHeight = PaneDimension(
        key: "fbloader.layout.bookDetailHeight", min: 380, ideal: 400, max: 1600)

    func restore(from defaults: UserDefaults) -> CGFloat {
        guard let stored = defaults.object(forKey: key) as? Double,
              stored.isFinite, stored > 0 else { return ideal }
        return clamped(CGFloat(stored))
    }

    /// Зона в момент скрытия/перестройки даёт 0 — такой замер не сохраняем.
    func save(_ value: CGFloat, to defaults: UserDefaults) {
        guard value.isFinite, value > 0 else { return }
        defaults.set(Double(clamped(value).rounded()), forKey: key)
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}
