import Foundation

/// A word that is not an action id, with the closest id when one is near.
public struct UnknownActionID: Error, Equatable, LocalizedError {
    public let id: String
    public let suggestion: String?

    /// What went wrong, then `next` (what the surface offers to do about it: list the actions, read the grammar).
    public func message(next: String) -> String {
        "\"\(id)\" is not an action id.\(suggestion.map { " Did you mean \"\($0)\"?" } ?? "") \(next)"
    }

    public var errorDescription: String? { message(next: "List the available actions to see the ids.") }
}
