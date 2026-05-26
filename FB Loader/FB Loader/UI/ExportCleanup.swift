import SwiftUI

/// Подписка на `progress.done` для инкрементального снятия галочки с книги
/// сразу после её успешной выгрузки. Реагирует только когда в `succeeded`
/// что-то есть — лишний холостой тик при появлении окна прогресса
/// (`done` стартует с `nil` → `Optional(0)`) отсекается.
///
/// Финальный пересчёт после `await ExportRunner.run` живёт отдельно —
/// его нельзя выразить как view-модификатор (он на уровне Task'а
/// в `runExport`), поэтому остаётся однострочником в каждом окне.
extension View {
    func onExportProgress(_ progress: ExportProgress?,
                          performCleanup: @escaping (ExportProgress) -> Void) -> some View {
        onChange(of: progress?.done) { _, _ in
            guard let progress, !progress.succeeded.isEmpty else { return }
            performCleanup(progress)
        }
    }
}
