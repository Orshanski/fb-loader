import Foundation

nonisolated struct Genre: Identifiable, Hashable, Sendable {
    let id: Int16
    let code: String
    /// Falls back to `code` for unknown codes.
    let name: String
    let parentID: Int16?
}
