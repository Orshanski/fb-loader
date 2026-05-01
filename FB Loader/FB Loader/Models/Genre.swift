import Foundation

nonisolated struct Genre: Identifiable, Hashable, Sendable {
    let id: Int16
    /// FB2 code, e.g. "sf_social", "sf_action".
    let code: String
    /// Human-readable name from genres.json. Falls back to `code` for unknown codes.
    let name: String
    let parentID: Int16?
}
