import Foundation

/// How the setup window writes a path.
public enum PathDisplay {
    /// A left-to-right isolate and its pop: what keeps a path in one piece, read left to right, inside a line written right
    /// to left. Without it a path that starts with an Arabic or Hebrew folder name takes the direction of that name and is
    /// laid out right to left, the slashes ending up on the wrong side of the names.
    static let leftToRightIsolate = "\u{2066}"
    static let popIsolate = "\u{2069}"

    /// `text` with every path under `home`, and `home` itself, written from `~`: shorter, and a screenshot of the window does
    /// not show the account name. For the doctor's sentences, which quote paths. Only a whole path counts: `/Users/ann` is
    /// not the start of `/Users/anna/x`, and `/Volumes/Backup/Users/ann/x` is another folder than the home.
    public static func abbreviatingHome(_ text: String, home: String) -> String {
        var home = home
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        guard home.count > 1 else { return text }
        // The characters a name of a folder can be made of, with the hyphen last so that it is not read as a range.
        let name = "\\p{L}\\p{N}._~"
        let pattern = "(?<![\(name)/-])" + NSRegularExpression.escapedPattern(for: home) + "(?=/|(?![\(name)-]))"
        return text.replacingOccurrences(of: pattern, with: "~", options: .regularExpression)
    }

    /// A whole path as a row of a list shows it: under `~` where it can be, and in one piece left to right. The marks that do
    /// that are invisible and not part of the path, so this is for text that is shown, not for text that is copied.
    public static func folder(_ path: String, home: String) -> String {
        leftToRightIsolate + abbreviatingHome(path, home: home) + popIsolate
    }
}
