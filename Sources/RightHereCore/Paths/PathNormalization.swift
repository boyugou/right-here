import Foundation

extension URL {
    /// Removes `.` and `..` components and repeated slashes without touching the file system.
    ///
    /// `standardizedFileURL` also rewrites `/private/tmp` to `/tmp` and likewise for `/var` and
    /// `/etc`, so a path Finder reported would be copied back in a different form. This keeps
    /// the path as given. Always use `.path` of the result: the URL never carries a trailing slash.
    public var lexicallyNormalized: URL {
        guard isFileURL else { return self }
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return URL(fileURLWithPath: "/" + parts.joined(separator: "/"), isDirectory: false)
    }
}
