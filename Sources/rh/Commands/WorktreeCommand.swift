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

struct WorktreeList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List active git worktrees."
    )

    @Argument(help: "Folder within the git repository (default: current directory).")
    var folder: String?

    @Flag(help: "Print output as JSON.")
    var json = false

    func run() async throws {
        let runtime = Runtime()
        let targetURL = folder.map { URL(fileURLWithPath: $0) } ?? runtime.facts.currentDirectory
        guard let root = runtime.facts.gitRoot(containing: targetURL) else {
            throw ValidationError("Not inside a git repository.")
        }
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
            let branch = entry.branch.map { " (\($0))" } ?? ""
            let bare = entry.isBare ? " [bare]" : ""
            let detached = entry.isDetached ? " [detached]" : ""
            Output.print("\(entry.path)\(branch)\(tag)\(bare)\(detached)")
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

    @Option(name: .customLong("folder"), help: "Folder within the git repository (default: current directory).")
    var folder: String?

    @Flag(help: "Print output as JSON.")
    var json = false

    func run() async throws {
        let runtime = Runtime()
        let targetURL = folder.map { URL(fileURLWithPath: $0) } ?? runtime.facts.currentDirectory
        guard let root = runtime.facts.gitRoot(containing: targetURL) else {
            throw ValidationError("Not inside a git repository.")
        }
        let result = try await GitWorktreeManager.prepareWorktree(gitRoot: root, branch: branch)
        if json {
            try Output.json(result)
            return
        }
        Output.print("Isolated worktree ready on branch '\(result.branch)': \(result.worktreeURL.path)")
    }
}

struct WorktreeRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove an isolated git worktree."
    )

    @Argument(help: "Worktree path or branch name to remove.")
    var target: String

    @Option(name: .customLong("folder"), help: "Folder within the git repository (default: current directory).")
    var folder: String?

    @Flag(name: .customLong("delete-branch"), help: "Also delete the branch after removing the worktree.")
    var deleteBranch = false

    func run() async throws {
        let runtime = Runtime()
        let targetURL = folder.map { URL(fileURLWithPath: $0) } ?? runtime.facts.currentDirectory
        guard let root = runtime.facts.gitRoot(containing: targetURL) else {
            throw ValidationError("Not inside a git repository.")
        }
        let list = try await GitWorktreeManager.listWorktrees(in: root)
        guard let match = list.first(where: { $0.path == target || $0.branch == target || $0.path.hasSuffix("/" + target) }) else {
            throw ValidationError("No worktree matching '\(target)' found in repository \(root.path).")
        }
        try await GitWorktreeManager.removeWorktree(worktreePath: match.path, gitRoot: root, deleteBranch: deleteBranch)
        Output.print("Removed worktree at \(match.path)")
    }
}
