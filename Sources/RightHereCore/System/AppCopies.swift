import Foundation

/// A copy of an app on disk, with its marketing version (`CFBundleShortVersionString`) when it has one.
public struct AppCopy: Sendable, Equatable {
    public var path: String
    public var version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}

/// The copies of Right Here that are installed. Spotlight and Launchpad open whichever they like, so a person with an old copy left in
/// `~/Applications` opened it and saw none of what the newer one has.
public enum AppCopies {
    /// The copies in an Applications folder (the Mac's or the person's own), newest first. A mounted disk image, a build folder and a
    /// download are not installed copies: they come and go, and nobody opens them by mistake for long.
    public static func installed(_ copies: [AppCopy], home: String) -> [AppCopy] {
        let folders = ["/Applications/", (home.hasSuffix("/") ? home : home + "/") + "Applications/"]
        var seen = Set<String>()
        return copies
            .filter { copy in folders.contains { copy.path.hasPrefix($0) } && seen.insert(copy.path).inserted }
            // Of two copies of one version, the Mac's Applications folder is the one to keep.
            .sorted { newer($0.version, than: $1.version) || (!newer($1.version, than: $0.version) && $0.path.hasPrefix("/Applications/") && !$1.path.hasPrefix("/Applications/")) }
    }

    /// The installed copy to keep instead of the one that runs, when there is one: a newer copy; or, when the one that runs is installed itself, the first of
    /// the installed copies, which is the newest and, of two of one version, the one in the Mac's Applications folder (the one the doctor says to keep). A copy
    /// that is not installed (a build folder, Homebrew's) gives way only to a newer one.
    public static func toKeep(instead running: AppCopy, among installed: [AppCopy]) -> AppCopy? {
        guard let first = installed.first, first.path != running.path else { return nil }
        if installed.contains(where: { $0.path == running.path }) { return first }
        return newer(first.version, than: running.version) ? first : nil
    }

    /// Whether version `a` is newer than `b`; a copy with no version is the oldest. The numbers of `1.10.2` count as numbers, and a part that
    /// is not one (`0.3.12b1`) counts by its numbers first; `1.0` and `1.0.0` are one version.
    public static func newer(_ a: String?, than b: String?) -> Bool {
        guard let a else { return false }
        guard let b else { return true }
        func trimmed(_ version: String) -> String {
            var parts = version.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            while parts.count > 1, parts.last == "0" { parts.removeLast() }
            return parts.joined(separator: ".")
        }
        return trimmed(a).compare(trimmed(b), options: .numeric) == .orderedDescending
    }
}
