import Foundation

/// What git says about one item and the repository git finds around it, for the repository actions (ADR 0033). `rh` reads it when such
/// an action is clicked and gives it to the planner, which stays pure; a planner without it refuses those actions.
public struct RepositoryState: Sendable, Equatable {
    /// What the item is in the checked-out commit.
    public enum Kind: Sendable, Equatable {
        case file
        case folder
        /// Another repository's commit, recorded in this one: its pages are in that repository.
        case submodule
    }

    /// The repository's top folder, as git names it (`rev-parse --show-toplevel`): git's own idea of the repository, which a `.git`
    /// folder that is not one does not change.
    public var root: URL?
    /// Why git could not read the repository.
    public enum GitProblem: Sendable, Equatable {
        /// There is no git to start: the Command Line Tools are not installed.
        case notInstalled
        /// What git said.
        case said(String)
        /// git failed and said nothing.
        case failedSilently
        /// The item resolves to a place outside the repository git found for it (a link that leads out of it).
        case outside(item: String, root: String)
    }

    /// Why git could not read the repository; the other fields are then empty.
    public var gitError: GitProblem?
    /// The item's path from the top folder, by segment: the names as the commit holds them when it is in the commit, else as they are on disk; empty
    /// for the top folder.
    public var itemPath: [String]
    /// The remote the link goes to: the first of the branch's upstream, its push remote, `origin` and the only remote that has the
    /// commit, else the first of them. Nil when none of these is there.
    public var remoteName: String?
    /// Every remote, for the sentence when none could be chosen.
    public var remoteNames: [String]
    /// What `git remote get-url` gives for the chosen remote.
    public var remoteURL: String?
    /// The checked-out commit's full hash; nil before the first commit.
    public var commit: String?
    /// The chosen remote has the commit (a branch of it contains it).
    public var isPushed: Bool
    /// The chosen remote pushes to another repository than the one it fetches from (`remote.<name>.pushurl`, `url.<base>.pushInsteadOf`): a push moves
    /// its branches too, so they do not tell whether the commit is in the repository the link goes to.
    public var pushesElsewhere: Bool
    /// What the item is in that commit; nil when it is not in it (a new or untracked file). `itemPath` then has the names as the commit holds them.
    public var kind: Kind?

    public init(root: URL?, gitError: GitProblem? = nil, itemPath: [String] = [], remoteName: String? = nil, remoteNames: [String] = [],
                remoteURL: String? = nil, commit: String? = nil, isPushed: Bool = false, pushesElsewhere: Bool = false, kind: Kind? = nil) {
        self.root = root
        self.gitError = gitError
        self.itemPath = itemPath
        self.remoteName = remoteName
        self.remoteNames = remoteNames
        self.remoteURL = remoteURL
        self.commit = commit
        self.isPushed = isPushed
        self.pushesElsewhere = pushesElsewhere
        self.kind = kind
    }
}
