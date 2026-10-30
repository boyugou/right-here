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
        let entries = GitWorktreeManager.parsePorcelain(porcelainZ(output), gitRoot: root)
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
    @Test func aNameThatMatchesSeveralOfTheWorktreesRightHereMadeRemovesNoneOfThem() throws {
        let root = URL(fileURLWithPath: "/work/app")
        let one = WorktreeEntry(path: "/work/app/.right-here/worktrees/a/feature", head: "1", branch: "a-feature")
        let two = WorktreeEntry(path: "/work/app/.right-here/worktrees/b/feature", head: "2", branch: "b-feature")
        // "feature" is the last part of both paths: guessing the first would remove a worktree the person did not name.
        #expect(throws: WorktreeError.ambiguous("feature", [one.path, two.path])) { try GitWorktreeManager.resolveManaged("feature", in: [one, two], gitRoot: root) }
        // Anything that names one of them exactly is not ambiguous.
        #expect(try GitWorktreeManager.resolveManaged(one.path, in: [one, two], gitRoot: root) == one)
        #expect(try GitWorktreeManager.resolveManaged("b-feature", in: [one, two], gitRoot: root) == two)
        // The person's own worktree of the same name is not Right Here's: it is never removed and does not make a name ambiguous.
        let mine = WorktreeEntry(path: "/work/feature", head: "3", branch: "feature")
        #expect(try GitWorktreeManager.resolveManaged("a-feature", in: [one, two, mine], gitRoot: root) == one)
        #expect(throws: WorktreeError.notCreatedHere(mine.path)) { try GitWorktreeManager.resolveManaged("feature", in: [mine], gitRoot: root) }
        #expect(throws: WorktreeError.notFound("nothing")) { try GitWorktreeManager.resolveManaged("nothing", in: [one, two, mine], gitRoot: root) }
    }

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

    @Test func twoRunsInOneSecondGetTwoWorktrees() async throws {
        // The default name was the time to the second: the second run took the first one's worktree for its own.
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let first = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: nil)
        let second = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: nil)
        #expect(first.wasCreated && second.wasCreated)
        #expect(first.branch != second.branch && first.worktreeURL != second.worktreeURL)
        #expect(first.branchCreated && second.branchCreated)
    }

    @Test func aFreshBranchNameIsAValidBranchAndIsNotTheSameTwice() {
        let names = (0..<50).map { _ in GitWorktreeManager.freshBranchName() }
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(name.hasPrefix("rh/"))
            #expect(GitWorktreeManager.branchNameRefusal(name) == nil, "\(name) is not a usable branch name")
        }
    }

    @Test func aWorktreeNothingWasDoneInIsRemovedWithTheBranchThisRunMade() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "unused")
        #expect(await GitWorktreeManager.discardIfUnchanged(made, gitRoot: repository))
        #expect(!FileManager.default.fileExists(atPath: made.worktreeURL.path))
        #expect(!(try git(["branch", "--list", "unused"], in: repository).contains("unused")))
    }

    @Test func aWorktreeWithAChangeIsKept() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "edited")
        try "a new file".write(to: made.worktreeURL.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        #expect(await GitWorktreeManager.discardIfUnchanged(made, gitRoot: repository) == false)
        #expect(FileManager.default.fileExists(atPath: made.worktreeURL.appendingPathComponent("new.txt").path))
        #expect(try git(["branch", "--list", "edited"], in: repository).contains("edited"))
    }

    @Test func aWorktreeThatExistedBeforeIsNeverRemoved() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        _ = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "older")
        let again = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "older")
        #expect(!again.wasCreated && !again.branchCreated)
        #expect(await GitWorktreeManager.discardIfUnchanged(again, gitRoot: repository) == false)
        #expect(FileManager.default.fileExists(atPath: again.worktreeURL.path))
    }

    @Test func aBranchThatWasAttachedIsKeptWhenItsWorktreeIsDiscarded() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        _ = try git(["branch", "existing"], in: repository)
        let attached = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "existing")
        #expect(attached.wasCreated && !attached.branchCreated)
        #expect(await GitWorktreeManager.discardIfUnchanged(attached, gitRoot: repository))
        #expect(!FileManager.default.fileExists(atPath: attached.worktreeURL.path))
        #expect(try git(["branch", "--list", "existing"], in: repository).contains("existing"), "a branch the run did not make is not deleted")
    }

    @Test func aWorktreeWithAChangeIsNotDiscardedEvenBeforeGitIsAskedToRemoveIt() async {
        // git itself refuses to remove a worktree with untracked files, which hides a missing check here: so the rule is tested
        // with a runner that reports a change, and expects that nothing is removed (only the drivers and the status are asked).
        let runner = FakeProcessRunner(results: [ProcessResult(status: 1), ProcessResult(status: 0, standardOutput: "?? new.txt\n")])
        let made = WorktreeResult(branch: "x", worktreeURL: URL(fileURLWithPath: "/tmp/rh-wt"), wasCreated: true, branchCreated: true)
        let removed = await GitWorktreeManager.discardIfUnchanged(made, gitRoot: URL(fileURLWithPath: "/tmp/rh-repo"), runner: runner)
        #expect(removed == false)
        #expect(runner.recorded.count == 2, "only the drivers and the status were asked; nothing was removed")
        #expect(runner.recorded.last?.arguments.contains("status") == true)
    }

    @Test func aWorktreeThisRunDidNotMakeIsNotDiscardedAndGitIsNotAsked() async {
        let runner = FakeProcessRunner()
        let existing = WorktreeResult(branch: "x", worktreeURL: URL(fileURLWithPath: "/tmp/rh-wt"), wasCreated: false, branchCreated: false)
        #expect(await GitWorktreeManager.discardIfUnchanged(existing, gitRoot: URL(fileURLWithPath: "/tmp/rh-repo"), runner: runner) == false)
        #expect(runner.recorded.isEmpty)
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

    @Test func aRefusedCreationLeavesNoTraceInTheRepository() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        // The branch name passes the rules, but git refuses it (a branch named like an existing directory of refs): nothing may be left behind.
        _ = try git(["branch", "taken"], in: repository)
        await #expect(throws: (any Error).self) { _ = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "taken/inner") }
        #expect(!FileManager.default.fileExists(atPath: repository.appendingPathComponent(".right-here").path))
        let exclude = try String(contentsOf: repository.appendingPathComponent(".git/info/exclude"), encoding: .utf8)
        #expect(!exclude.contains(".right-here"))
    }

    @Test func theExcludeLineIsAddedEvenWhenAComment_MentionsTheFolder() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let exclude = repository.appendingPathComponent(".git/info/exclude")
        try "# .right-here is mentioned here, but not ignored\n".write(to: exclude, atomically: true, encoding: .utf8)
        _ = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "feature")
        let lines = try String(contentsOf: exclude, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.contains(".right-here"))
        #expect(try git(["status", "--porcelain"], in: repository).isEmpty)
    }

    @Test func theRepositorysOwnHooksAndFiltersDoNotRunWhileAWorktreeIsMade() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let marker = repository.deletingLastPathComponent().appendingPathComponent("ran-\(UUID().uuidString)").path
        defer { for suffix in [".hook", ".smudge"] { try? FileManager.default.removeItem(atPath: marker + suffix) } }
        // A filter the repository's own configuration defines, selected by a committed attribute, and a post-checkout hook in its hooks folder.
        try "* filter=evil\n".write(to: repository.appendingPathComponent(".gitattributes"), atomically: true, encoding: .utf8)
        _ = try git(["add", ".gitattributes"], in: repository)
        _ = try git(["commit", "-q", "-m", "attributes"], in: repository)
        _ = try git(["config", "--local", "filter.evil.smudge", "touch \(marker).smudge"], in: repository)
        let hook = repository.appendingPathComponent(".git/hooks/post-checkout")
        try "#!/bin/sh\ntouch \(marker).hook\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "isolated")
        #expect(made.wasCreated)
        #expect(!FileManager.default.fileExists(atPath: marker + ".hook"), "the post-checkout hook ran")
        #expect(!FileManager.default.fileExists(atPath: marker + ".smudge"), "the repository's filter ran")
        #expect(try String(contentsOf: made.worktreeURL.appendingPathComponent("README.md"), encoding: .utf8) == "initial")
    }

    @Test func aWorktreeAttachesToAnExistingBranch() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        _ = try git(["branch", "existing"], in: repository)
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "existing")
        #expect(made.wasCreated && made.branch == "existing")
        #expect(FileManager.default.fileExists(atPath: made.worktreeURL.appendingPathComponent("README.md").path))
    }
}
