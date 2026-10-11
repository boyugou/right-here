import Foundation

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
    /// The root of the git working tree containing `url`. A repository rooted at the home
    /// directory is ignored: a dotfiles repository would otherwise claim every path.
    func gitRoot(containing url: URL) -> URL?
    func applicationURL(bundleID: String) -> URL?
    func isRunning(bundleID: String) -> Bool
    func environment(_ key: String) -> String?
}

extension SystemFacts {
    public var shellFlavor: ShellFlavor { ShellFlavor(loginShellPath: loginShell) }
}

/// A deterministic stand-in for the machine, used by tests across modules.
public struct FakeSystemFacts: SystemFacts {
    public var homeDirectory: URL
    public var currentDirectory: URL
    public var loginShell: String
    public var directories: Set<String>
    public var files: Set<String>
    public var gitRoots: [String]
    public var applications: [String: URL]
    public var runningApplications: Set<String>
    public var variables: [String: String]

    public init(
        homeDirectory: URL = URL(fileURLWithPath: "/Users/tester"),
        currentDirectory: URL = URL(fileURLWithPath: "/Users/tester"),
        loginShell: String = "/bin/zsh",
        directories: Set<String> = [],
        files: Set<String> = [],
        gitRoots: [String] = [],
        applications: [String: URL] = [:],
        runningApplications: Set<String> = [],
        variables: [String: String] = [:]
    ) {
        self.homeDirectory = homeDirectory
        self.currentDirectory = currentDirectory
        self.loginShell = loginShell
        self.directories = directories
        self.files = files
        self.gitRoots = gitRoots
        self.applications = applications
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

    public func gitRoot(containing url: URL) -> URL? {
        let path = url.lexicallyNormalized.path
        let home = homeDirectory.lexicallyNormalized.path
        let match = gitRoots
            .filter { $0 != home && (path == $0 || path.hasPrefix($0 + "/")) }
            .max { $0.count < $1.count }
        return match.map { URL(fileURLWithPath: $0) }
    }

    public func applicationURL(bundleID: String) -> URL? { applications[bundleID] }
    public func isRunning(bundleID: String) -> Bool { runningApplications.contains(bundleID) }
    public func environment(_ key: String) -> String? { variables[key] }
}
