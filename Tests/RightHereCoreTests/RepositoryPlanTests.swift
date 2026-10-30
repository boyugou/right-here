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

    private func state(remote: String? = "origin", names: [String] = ["origin"], url: String? = "git@github.com:owner/app.git",
                       commit: String? = nil, pushed: Bool = true, inCommit: Bool = true) -> RepositoryState {
        RepositoryState(root: root, remoteName: remote, remoteNames: names, remoteURL: url, commit: commit ?? self.commit, isPushed: pushed, isInCommit: inCommit)
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
        let made = try plan(.copyRepositoryLink, [folder, file], states: [folder: state(), file: state()])
        #expect(made.steps == [.copyToPasteboard("https://github.com/owner/app/tree/\(commit)/src\nhttps://github.com/owner/app/blob/\(commit)/src/main.swift")])
    }

    @Test func theRepositoryPageOpensForOneItemAndRefusesSeveral() throws {
        let made = try plan(.openRepositoryPage, [root], states: [root: state()])
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
        #expect(refusal(states: [file: RepositoryState(root: root, remoteName: "origin", remoteNames: ["origin"], remoteURL: "https://github.com/o/a",
                                                         commit: nil, isPushed: false, isInCommit: false)])?.contains("no commit") == true)
        #expect(refusal(states: [file: state(pushed: false)])?.contains("Push it") == true)
        #expect(refusal(states: [file: state(inCommit: false)])?.contains("not in the checked-out commit") == true)
    }

    @Test func onlyTheTwoRepositoryActionsReadTheRepository() {
        #expect(ActionRef.copyRepositoryLink.readsRepository && ActionRef.openRepositoryPage.readsRepository)
        #expect(!ActionRef.copyPath(.absolute).readsRepository && !ActionRef.reveal.readsRepository)
        #expect(ActionRef(parsing: "repository.copy-link") == .copyRepositoryLink && ActionRef(parsing: "repository.open-page") == .openRepositoryPage)
        #expect(ActionRef(parsing: "repository.copy-link@ghostty") == nil && ActionRef(parsing: "repository") == nil)
    }
}
