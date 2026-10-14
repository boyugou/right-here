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

public enum GitWorktreeManager {
    public static func gitRoot(containing url: URL, facts: any SystemFacts) -> URL? {
        facts.gitRoot(containing: url)
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
        let rhPrefix = gitRoot.appendingPathComponent(".right-here/worktrees").standardizedFileURL.path
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
                let isRightHere = standardPath.hasPrefix(rhPrefix) || (branch?.hasPrefix("rh/") == true)
                entries.append(WorktreeEntry(path: standardPath, head: head, branch: branch, isBare: isBare, isDetached: isDetached, isRightHere: isRightHere))
            }
        }
        return entries
    }

    public static func prepareWorktree(gitRoot: URL, branch preferredBranch: String?, runner: any ProcessRunner = LiveProcessRunner()) async throws -> WorktreeResult {
        let branchName: String
        if let preferred = preferredBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !preferred.isEmpty {
            branchName = preferred
        } else {
            branchName = "rh/\(Int(Date().timeIntervalSince1970))"
        }
        let sanitizedName = branchName.replacingOccurrences(of: "/", with: "-")
        let worktreesBase = gitRoot.appendingPathComponent(".right-here/worktrees").standardizedFileURL
        let worktreeDir = URL(fileURLWithPath: worktreesBase.appendingPathComponent(sanitizedName).path, isDirectory: true)

        try? FileManager.default.createDirectory(at: worktreesBase, withIntermediateDirectories: true)

        // Ensure .git/info/exclude ignores .right-here
        let excludeFile = gitRoot.appendingPathComponent(".git/info/exclude")
        if FileManager.default.fileExists(atPath: excludeFile.path) {
            if let content = try? String(contentsOf: excludeFile, encoding: .utf8), !content.contains(".right-here") {
                let newContent = content.hasSuffix("\n") ? "\(content).right-here\n" : "\(content)\n.right-here\n"
                try? newContent.write(to: excludeFile, atomically: true, encoding: .utf8)
            }
        }

        // If worktree directory already exists, return it
        if FileManager.default.fileExists(atPath: worktreeDir.path) {
            return WorktreeResult(branch: branchName, worktreeURL: worktreeDir, wasCreated: false)
        }

        // Try creating with a new branch
        let addStep = ProcessStep(executable: "/usr/bin/git", arguments: ["-C", gitRoot.path, "worktree", "add", "-b", branchName, worktreeDir.path, "HEAD"])
        let addResult = try await runner.run(addStep)
        if addResult.status == 0 {
            return WorktreeResult(branch: branchName, worktreeURL: worktreeDir, wasCreated: true)
        }

        // If branch already exists, attach to existing branch
        let fallbackStep = ProcessStep(executable: "/usr/bin/git", arguments: ["-C", gitRoot.path, "worktree", "add", worktreeDir.path, branchName])
        let fallbackResult = try await runner.run(fallbackStep)
        if fallbackResult.status == 0 {
            return WorktreeResult(branch: branchName, worktreeURL: worktreeDir, wasCreated: true)
        }

        let err = addResult.standardError.isEmpty ? fallbackResult.standardError : addResult.standardError
        throw ExecutionError.stepFailed(index: 0, step: "git worktree add", message: err.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func removeWorktree(worktreePath: String, gitRoot: URL, deleteBranch: Bool = false, runner: any ProcessRunner = LiveProcessRunner()) async throws {
        let removeStep = ProcessStep(executable: "/usr/bin/git", arguments: ["-C", gitRoot.path, "worktree", "remove", "--force", worktreePath])
        let removeResult = try await runner.run(removeStep)
        guard removeResult.status == 0 else {
            throw ExecutionError.stepFailed(index: 0, step: "git worktree remove", message: removeResult.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if deleteBranch {
            let list = try await listWorktrees(in: gitRoot, runner: runner)
            if let entry = list.first(where: { $0.path == worktreePath }), let branch = entry.branch {
                let deleteStep = ProcessStep(executable: "/usr/bin/git", arguments: ["-C", gitRoot.path, "branch", "-D", branch])
                _ = try? await runner.run(deleteStep)
            }
        }
    }
}
