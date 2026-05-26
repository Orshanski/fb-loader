import Foundation
import Observation

/// Mutated and read only on the main actor (matches `ExportRunner.run`).
/// `@MainActor` makes Swift 6 strict-concurrency happy.
@MainActor
@Observable
final class ExportProgress {
    var total: Int = 0
    var done: Int = 0
    var currentTitle: String = ""
    var cancelled: Bool = false
    var failed: [(title: String, error: String)] = []
    /// `libid` каждой книги, успешно записанной на диск. Растёт по мере
    /// выгрузки; читается родительской вьюхой через
    /// `removingSucceeded(from:)` для инкрементального снятия галочек.
    var succeeded: Set<Int32> = []

    /// Возвращает новый набор: переданный `set` минус libid'ы из `succeeded`.
    /// Возвращает значение, чтобы метод оставался pure и тестировался без
    /// зависимости от call-site'а — родительская вьюха сама решает, куда
    /// присвоить результат (`state.checkedBookLibids` или `coord.checkedBookLibids`).
    func removingSucceeded(from set: Set<Int32>) -> Set<Int32> {
        set.subtracting(succeeded)
    }
}
