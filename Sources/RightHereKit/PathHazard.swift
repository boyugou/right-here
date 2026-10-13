import Darwin
import Foundation

/// Questions about a path as written that only the file system can answer.
public enum PathHazard {
    /// True when a `..` follows a component that is a symbolic link: the kernel resolves `link/..` to the folder
    /// around the link's target, while reading the text alone (as `lexicallyNormalized` does) gives the folder around
    /// the link, so an action would run on a folder the person did not mean.
    ///
    /// The path is cut at slash scalars, as the kernel cuts it: a slash followed by a combining mark is one `Character`
    /// that is not "/", but the kernel still ends the component there, so reading by `Character` would miss a `..`.
    public static func linkBeforeDotDot(_ path: String) -> Bool {
        let dot = ".".unicodeScalars, dotDot = "..".unicodeScalars
        var names: [String] = []
        for component in path.unicodeScalars.split(separator: "/", omittingEmptySubsequences: true) {
            if component.elementsEqual(dot) { continue }
            if component.elementsEqual(dotDot) {
                if isSymbolicLink("/" + names.joined(separator: "/")) { return true }
                if !names.isEmpty { names.removeLast() }
                continue
            }
            names.append(String(String.UnicodeScalarView(component)))
        }
        return false
    }

    private static func isSymbolicLink(_ path: String) -> Bool {
        var status = stat()
        return lstat(path, &status) == 0 && (status.st_mode & S_IFMT) == S_IFLNK
    }
}
