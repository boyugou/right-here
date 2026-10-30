import Foundation
import RightHereCore

/// What the planner is told about a worktree that does not exist yet: every path below the worktree's root is the same path below the
/// repository's root, which is what the worktree will hold. So a request for `<worktree>/sub` is planned as the request for `<repository>/sub`
/// is, and a plan can be made before anything is created. Nothing is written. The worktree is made from the committed tree, so a file that
/// is only in the working copy is not in it: a plan that names one is refused when the worktree exists, and `rh run` plans again then.
public struct WorktreeFacts: SystemFacts {
    public let base: any SystemFacts
    public let repository: URL
    public let worktree: URL

    public init(base: any SystemFacts, repository: URL, worktree: URL) {
        self.base = base
        self.repository = repository.lexicallyNormalized
        self.worktree = worktree.lexicallyNormalized
    }

    /// The repository path that a path of the worktree stands for, or `nil` when the path is not in the worktree.
    private func repositoryPath(_ url: URL) -> URL? {
        let path = url.lexicallyNormalized.path
        let top = worktree.path
        guard path == top || path.hasPrefix(top + "/") else { return nil }
        return URL(fileURLWithPath: repository.path + path.dropFirst(top.count))
    }

    public var homeDirectory: URL { base.homeDirectory }
    public var currentDirectory: URL { base.currentDirectory }
    public var loginShell: String { base.loginShell }

    public func isDirectory(_ url: URL) -> Bool? {
        base.isDirectory(repositoryPath(url) ?? url)
    }

    public func fileExists(_ url: URL) -> Bool {
        base.fileExists(repositoryPath(url) ?? url)
    }

    public func itemState(_ url: URL) -> ItemState {
        base.itemState(repositoryPath(url) ?? url)
    }

    public func gitRoot(containing url: URL) -> URL? {
        repositoryPath(url) != nil ? worktree : base.gitRoot(containing: url)
    }

    public func onDiskPath(_ url: URL) -> String {
        guard repositoryPath(url) != nil else { return base.onDiskPath(url) }
        // The worktree's own name on disk, then the names below it as they were typed (it does not exist yet, so there is nothing else to read).
        return base.onDiskPath(worktree) + url.lexicallyNormalized.path.dropFirst(worktree.path.count)
    }

    public func applicationURL(bundleID: String) -> URL? { base.applicationURL(bundleID: bundleID) }
    public func displayName(bundleID: String) -> String? { base.displayName(bundleID: bundleID) }
    public func bundleVersion(bundleID: String) -> String? { base.bundleVersion(bundleID: bundleID) }
    public func applicationCopies(bundleID: String) -> [AppCopy] { base.applicationCopies(bundleID: bundleID) }
    public func isRunning(bundleID: String) -> Bool { base.isRunning(bundleID: bundleID) }
    public func environment(_ key: String) -> String? { base.environment(key) }
}
