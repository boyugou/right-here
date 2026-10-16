import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct WorktreeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "worktree",
        abstract: "Manage isolated git worktrees for actions and AI agents.",
        discussion: """
        Worktrees let AI coding agents and experiments run in an isolated git branch \
        without touching your active working tree or uncommitted files.

          rh worktree list               list active git worktrees
          rh worktree add feature-1      create an isolated worktree for branch feature-1
          rh worktree remove feature-1   remove an isolated worktree and prune
        """,
        subcommands: [
            WorktreeList.self,
            WorktreeAdd.self,
            WorktreeRemove.self
        ],
        defaultSubcommand: WorktreeList.self
    )
}

/// The repository that holds the folder a worktree command was given, or the current folder when it was given none.
enum WorktreeTarget {
    static func gitRoot(_ folder: String?, facts: any SystemFacts) throws -> URL {
        let target = folder.map { URL(fileURLWithPath: $0) } ?? facts.currentDirectory
        // A folder that is not there is a typo, and a typo is reported and never replaced by the repository around it (docs/DESIGN.md, 9.0).
        // `rh worktree ad` is the folder "ad" of `rh worktree list`, so a word like a subcommand's name is said to be a likely mistake.
        if let folder, facts.itemState(target) == .missing {
            let names = WorktreeCommand.configuration.subcommands.map { $0._commandName }
            let hint = InvocationCheck.subcommandHint(for: folder, of: "worktree", in: names).map { " " + $0 } ?? ""
            throw Output.fail("error: \(target.path.withControlCharactersEscaped) does not exist." + hint)
        }
        guard let root = facts.gitRoot(containing: target) else {
            throw ValidationError("Not inside a git repository.")
        }
        return root
    }
}

struct WorktreeList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List active git worktrees."
    )

    @Argument(help: "Folder within the git repository (default: current directory). One that does not exist is refused.")
    var folder: String?

    @Flag(help: "Print output as JSON.")
    var json = false

    func run() async throws {
        let runtime = Runtime()
        let root = try WorktreeTarget.gitRoot(folder, facts: runtime.facts)
        let list = try await GitWorktreeManager.listWorktrees(in: root)
        if json {
            try Output.json(list)
            return
        }
        if list.isEmpty {
            Output.print("No worktrees found.")
            return
        }
        for entry in list {
            let tag = entry.isRightHere ? " [rh]" : ""
            let branch = entry.branch.map { " (\($0.withControlCharactersEscaped))" } ?? ""
            let bare = entry.isBare ? " [bare]" : ""
            let detached = entry.isDetached ? " [detached]" : ""
            Output.print("\(entry.path.withControlCharactersEscaped)\(branch)\(tag)\(bare)\(detached)")
        }
    }
}

struct WorktreeAdd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Create an isolated git worktree branch."
    )

    @Argument(help: "Branch name to create or attach to.")
    var branch: String

    @Option(name: .customLong("folder"), help: "Folder within the git repository (default: current directory). One that does not exist is refused.")
    var folder: String?

    @Flag(help: "Print output as JSON.")
    var json = false

    func run() async throws {
        let runtime = Runtime()
        let root = try WorktreeTarget.gitRoot(folder, facts: runtime.facts)
        let result = try await GitWorktreeManager.prepareWorktree(gitRoot: root, branch: branch)
        if json {
            try Output.json(result)
            return
        }
        Output.print("Isolated worktree ready on branch '\(result.branch.withControlCharactersEscaped)': \(result.worktreeURL.path.withControlCharactersEscaped)")
    }
}

struct WorktreeRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a worktree that Right Here created.",
        discussion: """
        Only worktrees under .right-here/worktrees in the repository are removed; the main working copy and worktrees you made \
        yourself are never touched (use `git worktree remove` for those). A worktree with uncommitted work is kept unless \
        you pass --force, and a branch is deleted only when it is fully merged.
        """
    )

    @Argument(help: "Worktree path, branch name or folder name to remove.")
    var target: String

    @Option(name: .customLong("folder"), help: "Folder within the git repository (default: current directory). One that does not exist is refused.")
    var folder: String?

    @Flag(name: .customLong("delete-branch"), help: "Also delete the branch after removing the worktree (only when it is fully merged).")
    var deleteBranch = false

    @Flag(name: .customLong("force"), help: "Remove the worktree even if it has uncommitted changes, which are lost.")
    var force = false

    func run() async throws {
        let runtime = Runtime()
        let root = try WorktreeTarget.gitRoot(folder, facts: runtime.facts)
        let removal = try await GitWorktreeManager.removeWorktree(worktreePath: target, gitRoot: root, deleteBranch: deleteBranch, force: force)
        Output.print("Removed worktree at \(removal.path.withControlCharactersEscaped)")
        if removal.branchDeleted { Output.print("Deleted its branch.") }
        if let kept = removal.branchKept { Output.print("Kept its branch: \(kept.withControlCharactersEscaped)") }
    }
}
