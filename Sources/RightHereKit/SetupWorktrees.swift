import Foundation
import RightHereCore

/// A line of the setup window's list of worktrees.
public struct WorktreeRow: Sendable, Equatable, Identifiable {
    public let entry: WorktreeEntry
    /// The first worktree git lists is the repository's own folder.
    public let isMainWorkingCopy: Bool
    /// Right Here made it, under `.right-here/worktrees`: the one kind the window offers to remove. The main working copy and a
    /// worktree the person made themselves are not, and `GitWorktreeManager.removeWorktree` would refuse them anyway.
    public let canBeRemoved: Bool

    public var id: String { entry.path }

    /// The branch as the window writes it. A name that git accepts can hold characters that draw nothing or turn the text after them around
    /// (U+202E), so that one branch reads as another; those are shown as escapes. The branch itself, which removal and the actions use, is `entry.branch`.
    public var branchTitle: String? { entry.branch?.withControlCharactersEscaped }

    public init(entry: WorktreeEntry, isMainWorkingCopy: Bool, canBeRemoved: Bool) {
        self.entry = entry
        self.isMainWorkingCopy = isMainWorkingCopy
        self.canBeRemoved = canBeRemoved
    }
}

/// What the list of worktrees shows now.
public enum WorktreeListing: Sendable, Equatable {
    /// Nothing was asked for yet.
    case idle
    case loading
    case loaded([WorktreeRow])
    /// git said no, or could not be started: its words, or the system's.
    case failed(String)
}

public enum WorktreeRepositories {
    /// The git repositories that `folders` (the pinned folders, then the recent ones) are in: the root of each, once, in the order
    /// the folders come. A folder inside Right Here's own worktrees (`.right-here/worktrees/<name>`) counts for the repository above
    /// it, which is where the list of worktrees has to be asked. The app's own working folder is not a candidate: for an app
    /// started from the Dock or Finder it is `/` (measured with a launchd job), a place that says nothing about what the person
    /// works on, which is why the folders are what the repository is taken from.
    public static func among(_ folders: [String], facts: any SystemFacts) -> [URL] {
        var seen = Set<String>()
        var roots: [URL] = []
        for folder in folders {
            var start = folder
            if let range = start.range(of: "/" + GitWorktreeManager.folderName + "/") ?? start.range(of: "/" + GitWorktreeManager.folderName, options: [.anchored, .backwards]) {
                start = String(start[..<range.lowerBound])
            }
            guard !start.isEmpty, let root = facts.gitRoot(containing: URL(fileURLWithPath: start))?.standardizedFileURL else { continue }
            if seen.insert(root.path).inserted { roots.append(root) }
        }
        return roots
    }
}

/// Lists the worktrees of a repository and removes one, the way the setup window does it: Right Here's own worktrees only,
/// never forced, and the branch stays.
public struct WorktreeBrowser: Sendable {
    private let runner: any ProcessRunner

    public init(runner: any ProcessRunner = LiveProcessRunner()) {
        self.runner = runner
    }

    /// `.loaded` with a row for each worktree git lists, or `.failed` with why not.
    public func list(in root: URL) async -> WorktreeListing {
        do {
            return .loaded(Self.rows(try await GitWorktreeManager.listWorktrees(in: root, runner: runner), in: root))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func rows(_ entries: [WorktreeEntry], in root: URL) -> [WorktreeRow] {
        entries.enumerated().map { index, entry in
            let managed = (try? GitWorktreeManager.resolveManaged(entry.path, in: entries, gitRoot: root)) != nil
            return WorktreeRow(entry: entry, isMainWorkingCopy: index == 0, canBeRemoved: managed && entry.isRightHere && index != 0)
        }
    }

    /// Removes the worktree of `row`, which the person has been asked about. A row the window does not offer to remove is refused
    /// before git is asked. Git's own refusal (uncommitted work) comes back as the notice, in its words.
    public func remove(_ row: WorktreeRow, in root: URL) async -> SetupNotice {
        guard row.canBeRemoved else { return .notRemovable }
        do {
            let removal = try await GitWorktreeManager.removeWorktree(worktreePath: row.entry.path, gitRoot: root, deleteBranch: false, force: false, runner: runner)
            return .worktreeRemoved(removal.path)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
