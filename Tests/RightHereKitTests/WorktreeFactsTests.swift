import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("The planner's view of a worktree that does not exist yet")
struct WorktreeFactsTests {
    private let repository = URL(fileURLWithPath: "/Users/tester/repo")
    private var worktree: URL { repository.appendingPathComponent(".right-here/worktrees/rh-1") }

    private func facts() -> WorktreeFacts {
        let base = FakeSystemFacts(directories: ["/Users/tester/repo", "/Users/tester/repo/sub"], files: ["/Users/tester/repo/sub/a.txt"],
                                   gitRoots: ["/Users/tester/repo"])
        return WorktreeFacts(base: base, repository: repository, worktree: worktree)
    }

    @Test func thePathsBelowTheWorktreeAreThoseOfTheRepositoryAndTheRestAreUnchanged() {
        let view = facts()
        #expect(view.isDirectory(worktree) == true, "the worktree stands for the repository's root")
        #expect(view.isDirectory(worktree.appendingPathComponent("sub")) == true)
        #expect(view.itemState(worktree.appendingPathComponent("sub/a.txt")) == .present)
        #expect(view.itemState(worktree.appendingPathComponent("sub/nope.txt")) == .missing)
        #expect(view.isDirectory(repository.appendingPathComponent("sub")) == true)
        #expect(view.isDirectory(URL(fileURLWithPath: "/elsewhere")) == nil)
    }

    @Test func aPathBelowTheWorktreeBelongsToTheWorktreeAndTheRepositoryIsNotTakenForIt() {
        let view = facts()
        // A sibling whose name starts with the worktree's name is not inside it.
        let sibling = URL(fileURLWithPath: worktree.path + "-other")
        #expect(view.gitRoot(containing: worktree.appendingPathComponent("sub")) == worktree)
        #expect(view.gitRoot(containing: sibling) == repository, "a sibling is judged by the repository, not by the worktree")
        #expect(view.isDirectory(sibling) == nil)
    }

    @Test func theNameOnDiskIsTheWorktreesAndTheNamesBelowItAreAsTyped() {
        let view = facts()
        #expect(view.onDiskPath(worktree.appendingPathComponent("sub/New Name")) == worktree.path + "/sub/New Name")
        #expect(view.onDiskPath(repository.appendingPathComponent("sub")) == "/Users/tester/repo/sub")
    }
}
