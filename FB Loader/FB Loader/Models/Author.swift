import Foundation

struct Author: Identifiable, Hashable, Sendable {
    static let unknownID: Int32 = 0

    let id: Int32
    let lastName: String
    let firstName: String
    let middleName: String

    var displayName: String {
        if id == Author.unknownID { return "(Без автора)" }
        return [lastName, firstName, middleName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static var unknown: Author {
        Author(id: unknownID, lastName: "", firstName: "", middleName: "")
    }
}
