import Foundation

extension URL {
    /// Removes `.` and `..` components and repeated slashes without touching the file system.
    ///
    /// `standardizedFileURL` also rewrites `/private/tmp` to `/tmp` and likewise for `/var` and
    /// `/etc`, so a path Finder reported would be copied back in a different form. This keeps
    /// the path as given. Always use `.path` of the result: the URL never carries a trailing slash.
    ///
    /// The path is cut at slash *scalars*, as the kernel cuts it. Splitting on `Character` would miss a
    /// slash followed by a combining mark (one grapheme), so `a/<U+0301>/../b` would collapse to `b` here
    /// while the file system resolves it to `a/b`.
    public var lexicallyNormalized: URL {
        guard isFileURL else { return self }
        var parts: [String] = []
        var current = String.UnicodeScalarView()
        func finishComponent() {
            defer { current = String.UnicodeScalarView() }
            if current.isEmpty || current.elementsEqual(".".unicodeScalars) { return }
            if current.elementsEqual("..".unicodeScalars) {
                if !parts.isEmpty { parts.removeLast() }
                return
            }
            parts.append(String(current))
        }
        for scalar in path.unicodeScalars {
            if scalar == "/" { finishComponent() } else { current.append(scalar) }
        }
        finishComponent()
        return URL(fileURLWithPath: "/" + parts.joined(separator: "/"), isDirectory: false)
    }
}
