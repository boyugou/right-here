import Foundation
import Testing
@testable import RightHereCore

@Suite("Planner: repository links (ADR 0033)")
struct RepositoryPlanTests {
    private let commit = "d89f86032883bae7ef136d543343639777e2455a"
    private let root = URL(fileURLWithPath: "/Users/tester/code/app")
    private let file = URL(fileURLWithPath: "/Users/tester/code/app/src/main.swift")
    private let folder = URL(fileURLWithPath: "/Users/tester/code/app/src")
    private let facts = FakeSystemFacts(directories: ["/Users/tester", "/Users/tester/code/app", "/Users/tester/code/app/src"],
                                        files: ["/Users/tester/code/app/src/main.swift"], gitRoots: ["/Users/tester/code/app"])

    private func state(_ path: [String] = ["src", "main.swift"], kind: RepositoryState.Kind? = .file, remote: String? = "origin",
                       names: [String] = ["origin"], url: String? = "git@github.com:owner/app.git", commit: String? = nil, pushed: Bool = true) -> RepositoryState {
        RepositoryState(root: root, itemPath: path, remoteName: remote, remoteNames: names, remoteURL: url, commit: commit ?? self.commit, isPushed: pushed, kind: kind)
    }

    private func plan(_ ref: ActionRef, _ items: [URL], states: [URL: RepositoryState]) throws -> LaunchPlan {
        try Planner(facts: facts, repositories: states).plan(ref, context: HereContext(origin: .items, items: items))
    }

    private func refusal(_ ref: ActionRef = .copyRepositoryLink, _ items: [URL]? = nil, states: [URL: RepositoryState]) -> String? {
        do {
            _ = try plan(ref, items ?? [file], states: states)
            return nil
        } catch {
            return (error as? PlanError).map { $0.errorDescription ?? "" }
        }
    }

    @Test func aFileIsCopiedAsItsPageAtTheCheckedOutCommit() throws {
        let made = try plan(.copyRepositoryLink, [file], states: [file: state()])
        #expect(made.steps == [.copyToPasteboard("https://github.com/owner/app/blob/\(commit)/src/main.swift")])
        #expect(made.notices.contains { $0.contains("not committed") })
    }

    @Test func aFolderIsLinkedAsATreeAndSeveralItemsOnePerLine() throws {
        let made = try plan(.copyRepositoryLink, [folder, file], states: [folder: state(["src"], kind: .folder), file: state()])
        #expect(made.steps == [.copyToPasteboard("https://github.com/owner/app/tree/\(commit)/src\nhttps://github.com/owner/app/blob/\(commit)/src/main.swift")])
    }

    @Test func theRepositoryPageOpensForOneItemAndRefusesSeveral() throws {
        let made = try plan(.openRepositoryPage, [root], states: [root: state([], kind: .folder)])
        #expect(made.steps == [.openURL("https://github.com/owner/app/tree/\(commit)")])
        #expect(refusal(.openRepositoryPage, [folder, file], states: [folder: state(), file: state()])?.contains("one item") == true)
    }

    @Test func aPasswordInTheRemoteIsInNoPlan() throws {
        let at = "@"
        let made = try plan(.copyRepositoryLink, [file], states: [file: state(url: "https://someone:s3cr3t" + at + "github.com/owner/app.git")])
        let text = try String(decoding: JSONEncoder().encode(made), as: UTF8.self)
        #expect(!text.contains("s3cr3t") && !text.contains("someone"))
    }

    @Test func eachReasonForNoPageIsSaidSoThatThePersonKnowsWhatToDo() {
        #expect(refusal(states: [:])?.contains("was not read") == true)
        #expect(refusal(.copyRepositoryLink, [URL(fileURLWithPath: "/Users/tester")], states: [:])?.contains("not in a git repository") == true)
        #expect(refusal(states: [file: state(remote: nil, names: [])])?.contains("no remote") == true)
        #expect(refusal(states: [file: state(remote: nil, names: ["fork", "mine"])])?.contains("fork, mine") == true)
        #expect(refusal(states: [file: state(url: "git" + "@" + "git.example.com:team/app.git")])?.contains("is on git.example.com") == true)
        #expect(refusal(states: [file: state(url: "ext::sh -c x")])?.contains("is not one of a repository") == true)
        #expect(refusal(states: [file: state(url: "file:///etc/app.git")])?.contains("is not one of a repository") == true)
        #expect(refusal(states: [file: RepositoryState(root: root, remoteName: "origin", remoteNames: ["origin"], remoteURL: "https://github.com/o/a")])?
                .contains("no commit") == true)
        #expect(refusal(states: [file: state(pushed: false)])?.contains("Push it") == true)
        #expect(refusal(states: [file: state(kind: nil)])?.contains("not in the checked-out commit") == true)
        #expect(refusal(states: [file: state(kind: .submodule)])?.contains("is a submodule") == true)
        #expect(refusal(states: [file: RepositoryState(root: nil, gitError: "fatal: not a git repository: /nonexistent")])?
                .contains("fatal: not a git repository") == true, "git's own reason is not what the person is told")
    }

    @Test func onlyTheTwoRepositoryActionsReadTheRepository() {
        #expect(ActionRef.copyRepositoryLink.readsRepository && ActionRef.openRepositoryPage.readsRepository)
        #expect(!ActionRef.copyPath(.absolute).readsRepository && !ActionRef.reveal.readsRepository)
        #expect(ActionRef(parsing: "repository.copy-link") == .copyRepositoryLink && ActionRef(parsing: "repository.open-page") == .openRepositoryPage)
        #expect(ActionRef(parsing: "repository.copy-link@ghostty") == nil && ActionRef(parsing: "repository") == nil)
    }
}

@Suite("Planner: repository links, what the reader found")
struct RepositoryPlanFromReaderTests {
    private let commit = "d89f86032883bae7ef136d543343639777e2455a"

    /// The link is made from the path git's top folder gives and the kind the commit gives, not from the `.git` entry on disk and whether the
    /// disk holds a folder: an empty `sub/.git` folder is not a repository to git, and a committed link to a folder is a file in the commit.
    @Test func theLinkUsesThePathAndTheKindTheReaderFound() throws {
        let item = URL(fileURLWithPath: "/Users/tester/code/app/sub/alias")
        let facts = FakeSystemFacts(directories: ["/Users/tester", "/Users/tester/code/app", "/Users/tester/code/app/sub", "/Users/tester/code/app/sub/alias"],
                                    gitRoots: ["/Users/tester/code/app/sub"])
        let state = RepositoryState(root: URL(fileURLWithPath: "/Users/tester/code/app"), itemPath: ["sub", "alias"], remoteName: "origin",
                                    remoteNames: ["origin"], remoteURL: "https://github.com/o/app", commit: commit, isPushed: true, kind: .file)
        let made = try Planner(facts: facts, repositories: [item: state]).plan(.copyRepositoryLink, context: HereContext(origin: .items, items: [item]))
        #expect(made.steps == [.copyToPasteboard("https://github.com/o/app/blob/\(commit)/sub/alias")])
    }

    @Test func theMenuOffersTheRepositoryPageForOneItemOnly() {
        let registry = ActionRegistry(config: .default, facts: FakeSystemFacts())
        let one = HereContext(origin: .items, items: [URL(fileURLWithPath: "/a")])
        let two = HereContext(origin: .items, items: [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")])
        #expect(registry.info(.openRepositoryPage, context: one).available)
        #expect(!registry.info(.openRepositoryPage, context: two).available)
        #expect(registry.info(.copyRepositoryLink, context: two).available)
    }
}
