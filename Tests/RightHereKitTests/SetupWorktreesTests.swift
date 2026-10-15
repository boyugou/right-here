import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

private let root = URL(fileURLWithPath: "/work/app")

/// `git worktree list --porcelain` for a repository with its main working copy, two worktrees Right Here made, one the
/// person made by hand next to it, and the main working copy of another repository's branch named like Right Here's.
private let porcelain = """
worktree /work/app
HEAD aaaa
branch refs/heads/main

worktree /work/app/.right-here/worktrees/rh-1760000000
HEAD bbbb
branch refs/heads/rh/1760000000

worktree /work/app/.right-here/worktrees/fix-login
HEAD cccc
branch refs/heads/fix/login

worktree /work/app-hotfix
HEAD dddd
branch refs/heads/rh/hotfix

worktree /work/app-detached
HEAD eeee
detached
"""

@Suite("WorktreeRepositories")
struct WorktreeRepositoriesTests {
    private let facts = FakeSystemFacts(
        homeDirectory: URL(fileURLWithPath: "/Users/tester"),
        gitRoots: ["/Users/tester/Projects/app", "/Users/tester/Projects/web", "/Users/tester"]
    )

    @Test func theRepositoriesAreTheRootsOfTheFoldersInTheOrderTheFoldersCome() {
        let found = WorktreeRepositories.among([
            "/Users/tester/Projects/web", "/Users/tester/Projects/app/Sources/lib", "/Users/tester/Projects/web/docs"
        ], facts: facts)
        #expect(found.map(\.path) == ["/Users/tester/Projects/web", "/Users/tester/Projects/app"])
    }

    @Test func aFolderThatIsInNoRepositoryIsLeftOut() {
        #expect(WorktreeRepositories.among(["/Users/tester/Documents", "/tmp/scratch"], facts: facts).isEmpty)
    }

    @Test func aRepositoryAtTheHomeFolderIsNotOne() {
        // The facts ignore a repository rooted at the home folder (a dotfiles repository would claim every path).
        #expect(WorktreeRepositories.among(["/Users/tester/Documents"], facts: facts).isEmpty)
    }

    @Test func aFolderInsideRightHeresWorktreesCountsForTheRepositoryAboveIt() {
        let found = WorktreeRepositories.among([
            "/Users/tester/Projects/app/.right-here/worktrees/rh-1760000000", "/Users/tester/Projects/app/.right-here/worktrees",
            "/Users/tester/Projects/app/.right-here/worktrees/rh-1/Sources"
        ], facts: facts)
        #expect(found.map(\.path) == ["/Users/tester/Projects/app"])
    }

    @Test func noFoldersMeansNoRepositories() {
        #expect(WorktreeRepositories.among([], facts: facts).isEmpty)
    }

    @Test func theAppsOwnWorkingFolderIsNotWhereTheRepositoryComesFrom() {
        // For an app started from the Dock the current directory is `/`; this took it as the repository to list, so the list was empty.
        var launched = facts
        launched.currentDirectory = URL(fileURLWithPath: "/")
        launched.gitRoots = []
        #expect(WorktreeRepositories.among(["/Users/tester/Projects/app"], facts: launched).isEmpty)
        #expect(WorktreeRepositories.among([], facts: facts).isEmpty)
    }
}

@Suite("WorktreeBrowser: what the list offers")
struct WorktreeRowsTests {
    private func rows() -> [WorktreeRow] {
        WorktreeBrowser.rows(GitWorktreeManager.parsePorcelain(porcelain, gitRoot: root), in: root)
    }

    @Test func theFirstLineIsTheMainWorkingCopyAndNothingElseIs() {
        #expect(rows().map(\.isMainWorkingCopy) == [true, false, false, false, false])
    }

    @Test func onlyWhatRightHereMadeUnderItsFolderCanBeRemoved() {
        #expect(rows().map(\.canBeRemoved) == [false, true, true, false, false])
    }

    @Test func aWorktreeOutsideRightHeresFolderIsNotRemovableEvenWithABranchNamedLikeRightHeres() {
        // `isRightHere` is also true for a branch called rh/..., wherever the worktree is; the removal refuses it, so the window must not offer it.
        let hotfix = rows()[3]
        #expect(hotfix.entry.isRightHere)
        #expect(!hotfix.canBeRemoved)
    }

    @Test func aRowKeepsWhatGitSaid() {
        let detached = rows()[4]
        #expect(detached.entry.isDetached)
        #expect(detached.entry.branch == nil)
        #expect(rows()[1].entry.branch == "rh/1760000000")
        #expect(rows()[1].id == "/work/app/.right-here/worktrees/rh-1760000000")
    }
}

@Suite("WorktreeBrowser: listing and removing")
struct WorktreeBrowserTests {
    @Test func theListIsAskedOfGitInTheRepository() async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: porcelain)])
        let listing = await WorktreeBrowser(runner: runner).list(in: root)
        guard case .loaded(let rows) = listing else { Issue.record("not loaded: \(listing)"); return }
        #expect(rows.count == 5)
        #expect(runner.recorded == [ProcessStep(executable: "/usr/bin/git", arguments: ["-C", "/work/app", "worktree", "list", "--porcelain"])])
    }

    @Test func gitThatSaysNoIsShownInItsWords() async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 128, standardError: "fatal: not a git repository")])
        let listing = await WorktreeBrowser(runner: runner).list(in: root)
        guard case .failed(let message) = listing else { Issue.record("not failed: \(listing)"); return }
        #expect(message.contains("not a git repository"))
    }

    @Test func aRemovalAsksGitToRemoveThatWorktreeAndNothingElse() async throws {
        // The window used to run `git worktree remove --force` and then `git branch -D` for whatever row it was given.
        let target = "/work/app/.right-here/worktrees/rh-1760000000"
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: porcelain), ProcessResult(status: 0)])
        let browser = WorktreeBrowser(runner: runner)
        let row = try #require(WorktreeBrowser.rows(GitWorktreeManager.parsePorcelain(porcelain, gitRoot: root), in: root).first { $0.id == target })
        let notice = await browser.remove(row, in: root)
        #expect(notice == .worktreeRemoved(target))
        let arguments = runner.recorded.map(\.arguments)
        #expect(arguments == [["-C", "/work/app", "worktree", "list", "--porcelain"], ["-C", "/work/app", "worktree", "remove", "--", target]])
        #expect(!arguments.joined().contains("--force"))
        #expect(!arguments.contains { $0.contains("branch") })
    }

    @Test func gitsRefusalForUncommittedWorkIsTheNoticeAndNothingIsRetriedWithForce() async throws {
        let target = "/work/app/.right-here/worktrees/fix-login"
        let refusal = "fatal: '\(target)' contains modified or untracked files, use --force to delete it"
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: porcelain), ProcessResult(status: 128, standardError: refusal)])
        let row = try #require(WorktreeBrowser.rows(GitWorktreeManager.parsePorcelain(porcelain, gitRoot: root), in: root).first { $0.id == target })
        let notice = await WorktreeBrowser(runner: runner).remove(row, in: root)
        guard case .failed(let message) = notice else { Issue.record("not a failure: \(notice)"); return }
        #expect(message.contains("contains modified or untracked files"))
        #expect(message.contains("never discarded without --force"))
        #expect(runner.recorded.count == 2, "git was asked to remove once and not again")
        #expect(!runner.recorded.contains { $0.arguments.contains("--force") })
    }

    @Test(arguments: [0, 3, 4])
    func aRowTheWindowDoesNotOfferIsRefusedBeforeGitIsAsked(index: Int) async {
        let runner = FakeProcessRunner()
        let row = WorktreeBrowser.rows(GitWorktreeManager.parsePorcelain(porcelain, gitRoot: root), in: root)[index]
        #expect(!row.canBeRemoved)
        let notice = await WorktreeBrowser(runner: runner).remove(row, in: root)
        #expect(notice.isProblem)
        #expect(runner.recorded.isEmpty)
    }
}

/// The same against real git, in a throwaway repository: what the window does for a worktree with work in it, and for one without.
@Suite("WorktreeBrowser: real git")
struct WorktreeBrowserGitTests {
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

    @Test func aWorktreeWithWorkInItIsKeptAndOneWithoutItIsRemovedWithItsBranchKept() async throws {
        let repository = try makeRepository().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: repository) }
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "feature-x")
        let browser = WorktreeBrowser()

        guard case .loaded(let before) = await browser.list(in: repository) else { Issue.record("not loaded"); return }
        #expect(before.count == 2)
        #expect(before.first?.isMainWorkingCopy == true && before.first?.canBeRemoved == false)
        let row = try #require(before.first { $0.entry.branch == "feature-x" })
        #expect(row.canBeRemoved)

        // Work that is not committed: git refuses, the window says so in git's words, and everything is still there.
        let note = made.worktreeURL.appendingPathComponent("notes.txt")
        try "unsaved thoughts".write(to: note, atomically: true, encoding: .utf8)
        let refused = await browser.remove(row, in: repository)
        guard case .failed(let message) = refused else { Issue.record("not refused: \(refused)"); return }
        #expect(message.contains("untracked") || message.contains("modified"), "\(message)")
        #expect(FileManager.default.fileExists(atPath: note.path))

        // Without it: removed, and the branch is still there.
        try FileManager.default.removeItem(at: note)
        let removed = await browser.remove(row, in: repository)
        #expect(removed == .worktreeRemoved(row.entry.path))
        #expect(!FileManager.default.fileExists(atPath: made.worktreeURL.path))
        #expect(try git(["branch", "--list", "feature-x"], in: repository).contains("feature-x"))
    }
}
