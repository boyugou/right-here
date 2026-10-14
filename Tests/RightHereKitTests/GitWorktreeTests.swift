import Foundation
import Testing
@testable import RightHereKit

@Suite("GitWorktreeManager")
struct GitWorktreeTests {
    @Test func parsePorcelainCorrectlyExtractsEntries() {
        let root = URL(fileURLWithPath: "/Users/tester/repo")
        let output = """
        worktree /Users/tester/repo
        HEAD aabbcc112233
        branch refs/heads/main

        worktree /Users/tester/repo/.right-here/worktrees/feature-1
        HEAD 112233445566
        branch refs/heads/rh/feature-1

        worktree /Users/tester/repo/detached-tree
        HEAD 998877665544
        detached

        worktree /Users/tester/repo/bare-tree
        bare
        """
        let entries = GitWorktreeManager.parsePorcelain(output, gitRoot: root)
        #expect(entries.count == 4)

        #expect(entries[0].path == "/Users/tester/repo")
        #expect(entries[0].branch == "main")
        #expect(!entries[0].isRightHere)

        #expect(entries[1].path == "/Users/tester/repo/.right-here/worktrees/feature-1")
        #expect(entries[1].branch == "rh/feature-1")
        #expect(entries[1].isRightHere)

        #expect(entries[2].path == "/Users/tester/repo/detached-tree")
        #expect(entries[2].isDetached)

        #expect(entries[3].path == "/Users/tester/repo/bare-tree")
        #expect(entries[3].isBare)
    }

    @Test func worktreeLifecycleInGitRepo() async throws {
        let repoDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoDir) }

        // Setup git repo
        _ = try Shell.run("/usr/bin/git", args: ["-C", repoDir.path, "init"])
        _ = try Shell.run("/usr/bin/git", args: ["-C", repoDir.path, "config", "user.name", "Test User"])
        _ = try Shell.run("/usr/bin/git", args: ["-C", repoDir.path, "config", "user.email", "test"])
        let dummy = repoDir.appendingPathComponent("README.md")
        try "initial".write(to: dummy, atomically: true, encoding: .utf8)
        _ = try Shell.run("/usr/bin/git", args: ["-C", repoDir.path, "add", "README.md"])
        _ = try Shell.run("/usr/bin/git", args: ["-C", repoDir.path, "commit", "-m", "initial commit"])

        // 1. Prepare worktree
        let res1 = try await GitWorktreeManager.prepareWorktree(gitRoot: repoDir, branch: "test-feature")
        #expect(res1.wasCreated)
        #expect(res1.branch == "test-feature")
        #expect(FileManager.default.fileExists(atPath: res1.worktreeURL.path))

        // 2. Prepare again (idempotent)
        let res2 = try await GitWorktreeManager.prepareWorktree(gitRoot: repoDir, branch: "test-feature")
        #expect(!res2.wasCreated)
        #expect(res2.worktreeURL.path == res1.worktreeURL.path)

        // 3. List worktrees
        let list = try await GitWorktreeManager.listWorktrees(in: repoDir)
        #expect(list.contains { $0.path == res1.worktreeURL.path && $0.branch == "test-feature" })

        // 4. Remove worktree
        try await GitWorktreeManager.removeWorktree(worktreePath: res1.worktreeURL.path, gitRoot: repoDir, deleteBranch: true)
        #expect(!FileManager.default.fileExists(atPath: res1.worktreeURL.path))

        let listAfter = try await GitWorktreeManager.listWorktrees(in: repoDir)
        #expect(!listAfter.contains { $0.path == res1.worktreeURL.path })
    }
}
