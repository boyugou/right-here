import Foundation

/// What `lstat` says about a path.
public enum ItemState: Sendable, Equatable {
    /// Something is there: a file, a folder, or a link (one that points nowhere included).
    case present
    /// The system refused to say: no search permission on a folder above it, or a privacy-protected folder
    /// such as Desktop or Documents. Nothing is known about it, but a path that was just selected in Finder
    /// is not a typo, and it must not be treated as a folder (a file handed to a terminal runs).
    case unreadable
    case missing
}

/// Everything the planner needs to know about the machine. The live implementation lives in
/// RightHereKit; tests use `FakeSystemFacts`, so planning stays pure and deterministic.
public protocol SystemFacts: Sendable {
    var homeDirectory: URL { get }
    /// The directory a command-line invocation started in.
    var currentDirectory: URL { get }
    /// Absolute path of the user's login shell, for example `/bin/zsh`.
    var loginShell: String { get }

    /// `nil` when the item cannot be inspected (for example it no longer exists).
    func isDirectory(_ url: URL) -> Bool?
    func fileExists(_ url: URL) -> Bool
    /// What is at the path (`lstat`, not `stat`, so a link that points nowhere is `present`).
    func itemState(_ url: URL) -> ItemState
    /// The root of the git working tree containing `url`. A repository rooted at the home
    /// directory is ignored: a dotfiles repository would otherwise claim every path.
    func gitRoot(containing url: URL) -> URL?
    func applicationURL(bundleID: String) -> URL?
    /// The name the system shows for an installed app, in the system language.
    func displayName(bundleID: String) -> String?
    /// The marketing version of an installed app (`CFBundleShortVersionString`), such as "1.3.1".
    func bundleVersion(bundleID: String) -> String?
    func isRunning(bundleID: String) -> Bool
    func environment(_ key: String) -> String?
}

extension SystemFacts {
    public var shellFlavor: ShellFlavor { ShellFlavor(loginShellPath: loginShell) }
    public func displayName(bundleID: String) -> String? { nil }
    public func bundleVersion(bundleID: String) -> String? { nil }
    public func itemState(_ url: URL) -> ItemState { fileExists(url) ? .present : .missing }
    /// Whether the path is there as far as anyone can tell: a refusal to look is not "missing".
    public func itemExists(_ url: URL) -> Bool { itemState(url) != .missing }
}

/// A deterministic stand-in for the machine, used by tests across modules.
public struct FakeSystemFacts: SystemFacts {
    public var homeDirectory: URL
    public var currentDirectory: URL
    public var loginShell: String
    public var directories: Set<String>
    public var files: Set<String>
    /// Symbolic links that point nowhere: `itemState` sees them, `fileExists` does not.
    public var danglingLinks: Set<String>
    /// Paths the system refuses to look at (`itemState` is `unreadable`; `isDirectory` knows nothing).
    public var unreadablePaths: Set<String>
    public var gitRoots: [String]
    public var applications: [String: URL]
    public var bundleVersions: [String: String]
    public var runningApplications: Set<String>
    public var variables: [String: String]

    public init(
        homeDirectory: URL = URL(fileURLWithPath: "/Users/tester"),
        currentDirectory: URL = URL(fileURLWithPath: "/Users/tester"),
        loginShell: String = "/bin/zsh",
        directories: Set<String> = [],
        files: Set<String> = [],
        danglingLinks: Set<String> = [],
        unreadablePaths: Set<String> = [],
        gitRoots: [String] = [],
        applications: [String: URL] = [:],
        bundleVersions: [String: String] = [:],
        runningApplications: Set<String> = [],
        variables: [String: String] = [:]
    ) {
        self.homeDirectory = homeDirectory
        self.currentDirectory = currentDirectory
        self.loginShell = loginShell
        self.directories = directories
        self.files = files
        self.danglingLinks = danglingLinks
        self.unreadablePaths = unreadablePaths
        self.gitRoots = gitRoots
        self.applications = applications
        self.bundleVersions = bundleVersions
        self.runningApplications = runningApplications
        self.variables = variables
    }

    public func isDirectory(_ url: URL) -> Bool? {
        let path = url.lexicallyNormalized.path
        if directories.contains(path) { return true }
        if files.contains(path) { return false }
        return nil
    }

    public func fileExists(_ url: URL) -> Bool {
        let path = url.lexicallyNormalized.path
        return directories.contains(path) || files.contains(path)
    }

    public func itemState(_ url: URL) -> ItemState {
        let path = url.lexicallyNormalized.path
        if fileExists(url) || danglingLinks.contains(path) { return .present }
        return unreadablePaths.contains(path) ? .unreadable : .missing
    }

    public func gitRoot(containing url: URL) -> URL? {
        let path = url.lexicallyNormalized.path
        let home = homeDirectory.lexicallyNormalized.path
        let match = gitRoots
            .filter { $0 != home && (path == $0 || path.hasPrefix($0 + "/")) }
            .max { $0.count < $1.count }
        return match.map { URL(fileURLWithPath: $0) }
    }

    public func applicationURL(bundleID: String) -> URL? { applications[bundleID] }
    public func bundleVersion(bundleID: String) -> String? { bundleVersions[bundleID] }
    public func isRunning(bundleID: String) -> Bool { runningApplications.contains(bundleID) }
    public func environment(_ key: String) -> String? { variables[key] }
}
