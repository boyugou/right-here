import Foundation

/// An id made from a name: the lowercase ASCII letters and digits of it, joined by dashes (`Lazy Git` is `lazy-git`). What the config calls things by (`agent.<id>`, `preset.<id>`), and what a
/// tool names them with, so it is short and has nothing in it that a shell, a path or a pattern would read.
enum IDSlug {
    /// The longest id made from a name: one longer than a tool takes (the MCP tool's key is at most 200 characters) is of no use.
    static let maxLength = 48

    /// The slug of `name`, or `nil` when it has no letter or digit of an id (a name in another script).
    static func make(from name: String) -> String? {
        var slug = ""
        var pendingDash = false
        for scalar in name.lowercased().unicodeScalars {
            if (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57) {
                if pendingDash, !slug.isEmpty { slug += "-" }
                pendingDash = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        guard !slug.isEmpty else { return nil }
        if slug.count > maxLength { slug = String(slug.prefix(maxLength)).trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
        return slug
    }

    /// `slug`, or `slug-2`, `slug-3`… for the first that `isTaken` does not say is.
    static func unique(_ slug: String, isTaken: (String) -> Bool) -> String {
        var candidate = slug
        var number = 2
        while isTaken(candidate) {
            candidate = "\(slug)-\(number)"
            number += 1
        }
        return candidate
    }
}
