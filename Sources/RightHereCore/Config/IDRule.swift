import Foundation

/// What an id the user names may look like (apps, templates, variants, agents, and every word of an action id):
/// lowercase letters, digits and dashes, not starting with a dash (it would read as an option on a command line).
/// `ConfigSchema` publishes the same rule as a JSON Schema pattern, and a test holds the two together.
enum IDRule {
    static let pattern = "^[a-z0-9][a-z0-9-]*$"

    static func isValid(_ text: String) -> Bool {
        guard let first = text.utf8.first, first != UInt8(ascii: "-") else { return false }
        return text.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == UInt8(ascii: "-") }
    }
}
