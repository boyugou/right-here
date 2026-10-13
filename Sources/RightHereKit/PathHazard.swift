import Darwin
import Foundation

/// Questions about a path as written that only the file system can answer.
public enum PathHazard {
    /// True when a `..` follows a component that is a symbolic link: the kernel resolves `link/..` to the folder
    /// around the link's target, while reading the text alone (as `lexicallyNormalized` does) gives the folder around
    /// the link, so an action would run on a folder the person did not mean.
    public static func linkBeforeDotDot(_ path: String) -> Bool {
        guard path.contains("..") else { return false }
        var prefix = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            if component == "." { continue }
            if component == ".." {
                if isSymbolicLink(prefix.isEmpty ? "/" : prefix) { return true }
                if let slash = prefix.lastIndex(of: "/") { prefix = String(prefix[..<slash]) }
                continue
            }
            prefix += "/" + component
        }
        return false
    }

    private static func isSymbolicLink(_ path: String) -> Bool {
        var status = stat()
        return lstat(path, &status) == 0 && (status.st_mode & S_IFMT) == S_IFLNK
    }
}
