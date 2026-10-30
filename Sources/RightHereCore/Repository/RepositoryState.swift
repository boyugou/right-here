import Foundation

/// What git says about the repository around one item, for the repository actions (ADR 0033). `rh` reads it when such an action is
/// clicked and gives it to the planner, which stays pure; a planner without it refuses those actions.
public struct RepositoryState: Sendable, Equatable {
    /// The repository's top folder.
    public var root: URL
    /// The remote the link goes to: the branch's upstream, else `origin`, else the only one. Nil when none of these is there.
    public var remoteName: String?
    /// Every remote, for the sentence when none could be chosen.
    public var remoteNames: [String]
    /// What `git remote get-url` gives for the chosen remote.
    public var remoteURL: String?
    /// The checked-out commit's full hash; nil before the first commit.
    public var commit: String?
    /// The chosen remote has the commit (a branch of it contains it).
    public var isPushed: Bool
    /// The item is in that commit (a new or untracked file is not).
    public var isInCommit: Bool

    public init(root: URL, remoteName: String?, remoteNames: [String], remoteURL: String?, commit: String?, isPushed: Bool, isInCommit: Bool) {
        self.root = root
        self.remoteName = remoteName
        self.remoteNames = remoteNames
        self.remoteURL = remoteURL
        self.commit = commit
        self.isPushed = isPushed
        self.isInCommit = isInCommit
    }
}
