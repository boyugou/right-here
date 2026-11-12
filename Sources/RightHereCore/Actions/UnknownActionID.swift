import Foundation

/// A word that is not an action id, with the closest id when one is near.
public struct UnknownActionID: Error, Equatable, LocalizedError {
    public let id: String
    public let suggestion: String?

    /// What went wrong, then `next` (what the surface offers to do about it: list the actions, read the grammar). An agent's surface passes `Fence.wrap` as `quote`:
    /// the word is what it was given, and the id it is near can be one the config made.
    public func message(next: String, quote: (String) -> String = { "\"\($0)\"" }) -> String {
        "\(quote(id)) is not an action id.\(suggestion.map { " Did you mean \(quote($0))?" } ?? "") \(next)"
    }

    public var errorDescription: String? { message(next: "List the available actions to see the ids.") }
}
