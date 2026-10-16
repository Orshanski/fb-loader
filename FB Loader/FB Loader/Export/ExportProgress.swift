import Foundation
import Observation

/// Mutated and read only on the main actor (matches `ExportRunner.run`).
/// `@MainActor` makes Swift 6 strict-concurrency happy.
@MainActor
@Observable
final class ExportProgress: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
    var total: Int = 0
    var done: Int = 0
    var currentTitle: String = ""
    var cancelled: Bool = false
    var failed: [(title: String, error: String)] = []
    var abortReason: String? = nil
}
