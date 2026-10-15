import Foundation
import RightHereCore

public struct WorktreeEntry: Sendable, Codable, Equatable {
    public let path: String
    public let head: String
    public let branch: String?
    public let isBare: Bool
    public let isDetached: Bool
    public let isRightHere: Bool

    public init(path: String, head: String, branch: String?, isBare: Bool = false, isDetached: Bool = false, isRightHere: Bool = false) {
        self.path = path
        self.head = head
        self.branch = branch
        self.isBare = isBare
        self.isDetached = isDetached
        self.isRightHere = isRightHere
    }
}

public struct WorktreeResult: Sendable, Codable, Equatable {
    public let branch: String
    public let worktreeURL: URL
    public let wasCreated: Bool

    public init(branch: String, worktreeURL: URL, wasCreated: Bool) {
        self.branch = branch
        self.worktreeURL = worktreeURL
        self.wasCreated = wasCreated
    }
}

/// What a removal did.
public struct WorktreeRemoval: Sendable, Codable, Equatable {
    public let path: String
    /// The branch was deleted too; `false` when it was not asked for or git kept it (see `branchKept`).
    public let branchDeleted: Bool
    /// Why the branch is still there when its deletion was asked for.
    public let branchKept: String?
}

/// Why a worktree request was refused.
public enum WorktreeError: Error, Equatable, LocalizedError {
    case invalidBranch(String)
    case directoryInTheWay(String)
    case notFound(String)
    case notCreatedHere(String)
    case ambiguous(String, [String])

    public var errorDescription: String? {
        switch self {
        case .invalidBranch(let reason): return "Not a usable branch name: \(reason)."
        case .directoryInTheWay(let detail): return detail
        case .notFound(let target): return "No worktree matching \"\(target.withControlCharactersEscaped)\" in this repository."
        case .notCreatedHere(let path):
            return "\(path.withControlCharactersEscaped) is not a worktree Right Here created (those live under .right-here/worktrees), so it is left alone. Use `git worktree remove` for it."
        case .ambiguous(let target, let paths):
            return "\"\(target.withControlCharactersEscaped)\" matches several worktrees: \(paths.map(\.withControlCharactersEscaped).joined(separator: ", ")). Name one by its path."
        }
    }
}

public enum GitWorktreeManager {
    /// The folder, below the repository's root, that holds the worktrees Right Here creates.
    public static let folderName = ".right-here/worktrees"

    public static func gitRoot(containing url: URL, facts: any SystemFacts) -> URL? {
        facts.gitRoot(containing: url)
    }

    /// Why `name` cannot be a branch name, or `nil`. A name starting with a dash would be read by git as an option; the
    /// rest are git's own rules (`git check-ref-format`) plus no whitespace or control character, because the name
    /// becomes a folder name that is typed into a terminal.
    public static func branchNameRefusal(_ name: String) -> String? {
        if name.isEmpty { return "it is empty" }
        if name.utf8.count > 200 { return "it is longer than 200 bytes" }
        if name.hasPrefix("-") { return "it starts with a dash, which git would read as an option" }
        if name == "@" || name == "HEAD" { return "\"\(name)\" is reserved by git" }
        let forbidden = Set("~^:?*[\\".unicodeScalars)
        if name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || $0.properties.isWhitespace || forbidden.contains($0) }) {
            return "it has a space, a control character or one of ~ ^ : ? * [ \\"
        }
        if name.contains("..") || name.contains("@{") || name.contains("//") { return "it has \"..\", \"@{\" or \"//\"" }
        if name.hasPrefix("/") || name.hasSuffix("/") || name.hasSuffix(".") { return "it starts or ends with a slash, or ends with a dot" }
        for component in name.split(separator: "/") where component.hasPrefix(".") || component.hasSuffix(".lock") {
            return "a part of it starts with a dot or ends with .lock"
        }
        return nil
    }

    /// Where the worktree of `branch` lives: one folder under `.right-here/worktrees`, the slashes of the name written as dashes.
    public static func worktreeDirectory(gitRoot: URL, branch: String) -> URL {
        let base = gitRoot.appendingPathComponent(folderName, isDirectory: true).standardizedFileURL
        return base.appendingPathComponent(branch.replacingOccurrences(of: "/", with: "-"), isDirectory: true)
    }

    public static func listWorktrees(in gitRoot: URL, runner: any ProcessRunner = LiveProcessRunner()) async throws -> [WorktreeEntry] {
        let step = ProcessStep(executable: "/usr/bin/git", arguments: ["-C", gitRoot.path, "worktree", "list", "--porcelain"])
        let result = try await runner.run(step)
        guard result.status == 0 else {
            throw ExecutionError.stepFailed(index: 0, step: "git worktree list", message: result.standardError)
        }
        return parsePorcelain(result.standardOutput, gitRoot: gitRoot)
    }

    public static func parsePorcelain(_ text: String, gitRoot: URL) -> [WorktreeEntry] {
        var entries: [WorktreeEntry] = []
        let blocks = text.components(separatedBy: "\n\n")
        let rhPrefix = gitRoot.appendingPathComponent(folderName).standardizedFileURL.path
        for block in blocks {
            let lines = block.split(separator: "\n").map(String.init)
            var path = ""
            var head = ""
            var branch: String? = nil
            var isBare = false
            var isDetached = false
            for line in lines {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    head = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch ") {
                    let ref = String(line.dropFirst("branch ".count))
                    branch = ref.replacingOccurrences(of: "refs/heads/", with: "")
                } else if line == "bare" {
                    isBare = true
                } else if line == "detached" {
                    isDetached = true
                }
            }
            if !path.isEmpty {
                let standardPath = URL(fileURLWithPath: path).standardizedFileURL.path
                let isRightHere = standardPath.hasPrefix(rhPrefix + "/") || (branch?.hasPrefix("rh/") == true)
                entries.append(WorktreeEntry(path: standardPath, head: head, branch: branch, isBare: isBare, isDetached: isDetached, isRightHere: isRightHere))
            }
        }
        return entries
    }

    public static func prepareWorktree(gitRoot: URL, branch preferredBranch: String?, runner: any ProcessRunner = LiveProcessRunner()) async throws -> WorktreeResult {
        let branchName: String
        if let preferred = preferredBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !preferred.isEmpty {
            if let refusal = branchNameRefusal(preferred) { throw WorktreeError.invalidBranch(refusal) }
            branchName = preferred
        } else {
            branchName = "rh/\(Int(Date().timeIntervalSince1970))"
        }
        let worktreesBase = gitRoot.appendingPathComponent(folderName, isDirectory: true).standardizedFileURL
        let worktreeDir = worktreeDirectory(gitRoot: gitRoot, branch: branchName)
        // The name has no dot-only part and no slash left, so the folder is directly below the base; check it all the same.
        guard worktreeDir.path.hasPrefix(worktreesBase.path + "/") else { throw WorktreeError.invalidBranch("it names a folder outside \(folderName)") }

        // The folder is only reused when git knows it as the worktree of this very branch: a folder that is there for another
        // reason, or the worktree of another branch whose name has the same dashes, is not an isolated copy of what was asked for.
        if FileManager.default.fileExists(atPath: worktreeDir.path) {
            let known = try await listWorktrees(in: gitRoot, runner: runner)
            let here = worktreeDir.resolvingSymlinksInPath().path
            guard let entry = known.first(where: { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == here }) else {
                throw WorktreeError.directoryInTheWay("\(worktreeDir.path.withControlCharactersEscaped) already exists and is not a git worktree. Move it away or choose another branch name.")
            }
            guard entry.branch == branchName else {
                throw WorktreeError.directoryInTheWay("\(worktreeDir.path.withControlCharactersEscaped) is the worktree of branch \"\((entry.branch ?? "(detached)").withControlCharactersEscaped)\", not \"\(branchName)\". Choose another branch name.")
            }
            return WorktreeResult(branch: branchName, worktreeURL: worktreeDir, wasCreated: false)
        }

        try? FileManager.default.createDirectory(at: worktreesBase, withIntermediateDirectories: true)
        keepOutOfGitStatus(gitRoot: gitRoot)

        // Try creating with a new branch
        let addStep = ProcessStep(executable: "/usr/bin/git", arguments: ["-C", gitRoot.path, "worktree", "add", "-b", branchName, worktreeDir.path, "HEAD"])
        let addResult = try await runner.run(addStep)
        if addResult.status == 0 {
            return WorktreeResult(branch: branchName, worktreeURL: worktreeDir, wasCreated: true)
        }

        // If branch already exists, attach to existing branch
        let fallbackStep = ProcessStep(executable: "/usr/bin/git", arguments: ["-C", gitRoot.path, "worktree", "add", "--", worktreeDir.path, branchName])
        let fallbackResult = try await runner.run(fallbackStep)
        if fallbackResult.status == 0 {
            return WorktreeResult(branch: branchName, worktreeURL: worktreeDir, wasCreated: true)
        }

        let err = addResult.standardError.isEmpty ? fallbackResult.standardError : addResult.standardError
        throw ExecutionError.stepFailed(index: 0, step: "git worktree add", message: err.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The worktree `target` names (its path, its branch or the last part of its path), among those Right Here created. Anything
    /// else in the repository, the main working copy and the person's own worktrees included, is never removed by Right Here.
    public static func resolveManaged(_ target: String, in list: [WorktreeEntry], gitRoot: URL) throws -> WorktreeEntry {
        let base = gitRoot.appendingPathComponent(folderName).standardizedFileURL.resolvingSymlinksInPath().path + "/"
        func resolved(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
        let wanted = resolved(target)
        func names(_ entry: WorktreeEntry) -> Bool {
            resolved(entry.path) == wanted || entry.branch == target || URL(fileURLWithPath: entry.path).lastPathComponent == target
        }
        let named = list.filter(names)
        let managed = named.filter { resolved($0.path).hasPrefix(base) }
        if managed.count == 1, let only = managed.first { return only }
        if managed.count > 1 { throw WorktreeError.ambiguous(target, managed.map(\.path)) }
        if let other = named.first { throw WorktreeError.notCreatedHere(other.path) }
        throw WorktreeError.notFound(target)
    }

    /// Removes a worktree Right Here created. Without `force` git refuses when the worktree has uncommitted work, and
    /// that refusal is passed on; the branch is deleted only with `git branch -d`, which keeps one that is not merged.
    @discardableResult
    public static func removeWorktree(
        worktreePath: String, gitRoot: URL, deleteBranch: Bool = false, force: Bool = false, runner: any ProcessRunner = LiveProcessRunner()
    ) async throws -> WorktreeRemoval {
        let entry = try resolveManaged(worktreePath, in: try await listWorktrees(in: gitRoot, runner: runner), gitRoot: gitRoot)
        var arguments = ["-C", gitRoot.path, "worktree", "remove"]
        if force { arguments.append("--force") }
        arguments += ["--", entry.path]
        let removed = try await runner.run(ProcessStep(executable: "/usr/bin/git", arguments: arguments))
        guard removed.status == 0 else {
            let detail = removed.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = force ? "" : " Uncommitted work is never discarded without --force."
            throw ExecutionError.stepFailed(index: 0, step: "git worktree remove", message: detail + hint)
        }
        guard deleteBranch, let branch = entry.branch else {
            return WorktreeRemoval(path: entry.path, branchDeleted: false, branchKept: nil)
        }
        let deleted = try await runner.run(ProcessStep(executable: "/usr/bin/git", arguments: ["-C", gitRoot.path, "branch", "-d", "--", branch]))
        if deleted.status == 0 { return WorktreeRemoval(path: entry.path, branchDeleted: true, branchKept: nil) }
        let why = deleted.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorktreeRemoval(path: entry.path, branchDeleted: false, branchKept: why.isEmpty ? "git kept the branch" : why)
    }

    /// `.right-here` is Right Here's folder inside the repository: its own copy of the person's work must not show up as untracked
    /// files. Done in the repository's `info/exclude`, which is not committed; a repository whose `.git` is a file (itself a worktree) is left alone.
    private static func keepOutOfGitStatus(gitRoot: URL) {
        let excludeFile = gitRoot.appendingPathComponent(".git/info/exclude")
        guard FileManager.default.fileExists(atPath: excludeFile.path),
              let content = try? String(contentsOf: excludeFile, encoding: .utf8), !content.contains(".right-here") else { return }
        let newContent = content.hasSuffix("\n") ? "\(content).right-here\n" : "\(content)\n.right-here\n"
        try? newContent.write(to: excludeFile, atomically: true, encoding: .utf8)
    }
}
