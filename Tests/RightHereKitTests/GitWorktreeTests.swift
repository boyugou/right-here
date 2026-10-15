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

/// What Right Here may remove and what it refuses to create. These run the real `git` in a throwaway repository.
@Suite("GitWorktreeManager safety")
struct GitWorktreeSafetyTests {
    private func git(_ arguments: [String], in directory: URL) throws -> String {
        try Shell.run("/usr/bin/git", args: ["-C", directory.path, "-c", "commit.gpgsign=false", "-c", "user.name=Test", "-c", "user.email=test"] + arguments)
    }

    private func makeRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        _ = try git(["init", "-q"], in: directory)
        try "initial".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        _ = try git(["add", "README.md"], in: directory)
        _ = try git(["commit", "-q", "-m", "initial"], in: directory)
        return directory
    }

    @Test(arguments: ["-b", "--detach", "-x", "", "   ", ".", "..", "a..b", "a b", "a\nb", "a\tb", "x.lock", "/x", "x/", "a//b", "@{u}", "@", "HEAD", "a~1", "a^", "a:b", "a?", "a*", "a[b", "a\\b", ".hidden", "ok/.hidden", "x.", "ok/y.lock"])
    func aNameGitCannotUseOrWouldReadAsAnOptionIsRefused(name: String) {
        #expect(GitWorktreeManager.branchNameRefusal(name) != nil, "\(name.debugDescription) was accepted")
    }

    @Test(arguments: ["feature-1", "rh/fix_2", "fix/issue-123", "release/1.2.3", "修复", "a.b", "v1.0"])
    func ordinaryBranchNamesAreAccepted(name: String) {
        #expect(GitWorktreeManager.branchNameRefusal(name) == nil)
    }

    @Test func aRefusedNameCreatesNothingAtAll() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        for name in ["-b", "..", "a b"] {
            await #expect(throws: WorktreeError.self) { _ = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: name) }
        }
        #expect(!FileManager.default.fileExists(atPath: repository.appendingPathComponent(".right-here").path))
        #expect(try git(["branch", "--list"], in: repository).split(separator: "\n").count == 1)
    }

    @Test func aFolderThatIsNotAWorktreeIsNotTakenForOne() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let folder = GitWorktreeManager.worktreeDirectory(gitRoot: repository, branch: "feature")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await #expect(throws: WorktreeError.self) { _ = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "feature") }
    }

    @Test func theWorktreeOfAnotherBranchWithTheSameDashesIsNotReused() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let first = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "a/b")
        #expect(first.wasCreated)
        // `a-b` is the same folder name as `a/b`; it must not hand back the other branch's checkout as its own.
        await #expect(throws: WorktreeError.self) { _ = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "a-b") }
    }

    @Test func aWorktreeThePersonMadeIsNeverRemoved() async throws {
        let repository = try makeRepository()
        let own = repository.deletingLastPathComponent().appendingPathComponent("own-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: repository); try? FileManager.default.removeItem(at: own) }
        _ = try git(["worktree", "add", "-q", "-b", "mine", own.path], in: repository)
        for target in [own.path, "mine", own.lastPathComponent, repository.path] {
            await #expect(throws: WorktreeError.self) { _ = try await GitWorktreeManager.removeWorktree(worktreePath: target, gitRoot: repository, deleteBranch: true, force: true) }
        }
        #expect(FileManager.default.fileExists(atPath: own.appendingPathComponent("README.md").path))
        #expect(FileManager.default.fileExists(atPath: repository.appendingPathComponent("README.md").path))
    }

    @Test func uncommittedWorkIsKeptUntilForceIsGiven() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "scratch")
        let work = made.worktreeURL.appendingPathComponent("notes.txt")
        try "unsaved thoughts".write(to: work, atomically: true, encoding: .utf8)
        await #expect(throws: (any Error).self) { _ = try await GitWorktreeManager.removeWorktree(worktreePath: "scratch", gitRoot: repository) }
        #expect(FileManager.default.fileExists(atPath: work.path))
        try await GitWorktreeManager.removeWorktree(worktreePath: "scratch", gitRoot: repository, force: true)
        #expect(!FileManager.default.fileExists(atPath: made.worktreeURL.path))
    }

    @Test func aBranchWithWorkThatIsNotMergedIsKept() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "experiment")
        _ = try git(["commit", "-q", "--allow-empty", "-m", "work that exists nowhere else"], in: made.worktreeURL)
        let removal = try await GitWorktreeManager.removeWorktree(worktreePath: made.worktreeURL.path, gitRoot: repository, deleteBranch: true, force: true)
        #expect(!removal.branchDeleted)
        #expect(removal.branchKept != nil)
        #expect(try git(["branch", "--list", "experiment"], in: repository).contains("experiment"))
    }

    @Test func aMergedBranchIsDeletedWithItsWorktree() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "done")
        let removal = try await GitWorktreeManager.removeWorktree(worktreePath: "done", gitRoot: repository, deleteBranch: true)
        #expect(removal.branchDeleted)
        #expect(!FileManager.default.fileExists(atPath: made.worktreeURL.path))
        #expect(!(try git(["branch", "--list", "done"], in: repository).contains("done")))
    }
}
