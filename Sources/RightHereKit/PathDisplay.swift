import Foundation

/// How the setup window writes a path.
public enum PathDisplay {
    /// A left-to-right isolate and its pop: what keeps a path in one piece, read left to right, inside a line written right
    /// to left. Without it a path that starts with an Arabic or Hebrew folder name takes the direction of that name and is
    /// laid out right to left, the slashes ending up on the wrong side of the names.
    static let leftToRightIsolate = "\u{2066}"
    static let leftToRightMark = "\u{200E}"
    static let popIsolate = "\u{2069}"

    /// `text` with every path under `home`, and `home` itself, written from `~`: shorter, and a screenshot of the window does
    /// not show the account name. For the doctor's sentences, which quote paths. Only a whole path counts: `/Users/tester` is
    /// not the start of `/Users/tester2/x`, and `/Volumes/Backup/Users/tester/x` is another folder than the home.
    public static func abbreviatingHome(_ text: String, home: String) -> String {
        var home = home
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        guard home.count > 1 else { return text }
        // The characters a name of a folder can be made of, with the hyphen last so that it is not read as a range.
        let name = "\\p{L}\\p{N}._~"
        let pattern = "(?<![\(name)/-])" + NSRegularExpression.escapedPattern(for: home) + "(?=/|(?![\(name)-]))"
        return text.replacingOccurrences(of: pattern, with: "~", options: .regularExpression)
    }

    /// A whole path as a row of a list shows it: under `~` where it can be, and in one piece left to right. In a right-to-left
    /// window the slashes between names are the neutral characters that decide the order: between two right-to-left names they
    /// take their direction, and the names come out in reverse. A left-to-right mark on each side of a slash makes it strong, so
    /// every name keeps its place. The marks are invisible and are not part of the path, so this is for text that is shown and
    /// never for text that is copied.
    public static func folder(_ path: String, home: String) -> String {
        let separated = abbreviatingHome(path, home: home)
            .split(separator: "/", omittingEmptySubsequences: false)
            .joined(separator: leftToRightMark + "/" + leftToRightMark)
        // A mark, not an isolate, at the start: the direction of a line is taken from its first strong character outside any isolate,
        // and an isolate hides every character of the path from that choice.
        return leftToRightMark + separated
    }
}
