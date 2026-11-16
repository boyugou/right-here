import Foundation
import Testing
import RightHereCore
import RightHereKit
@testable import AppModel

private let firstRoot = URL(fileURLWithPath: "/work/first")
private let secondRoot = URL(fileURLWithPath: "/work/second")

/// Git's answers are captured when a read starts. A test may hold those answers and return them in either order.
private actor WorktreeRunner: ProcessRunner {
    private struct HeldRead {
        let response: ProcessResult
        let continuation: CheckedContinuation<ProcessResult, Never>
    }

    private var held: [Int: HeldRead] = [:]
    private var nextRead = 0
    private(set) var calls: [ProcessStep] = []
    private(set) var removedFrom: [String] = []
    private var holdReads = false
    private var holdAfterRemoval = false
    private var removalFails = false
    private var listingFails = false
    private var removed = Set<String>()

    var pendingIDs: [Int] { held.keys.sorted() }

    func holdReads(_ value: Bool) { holdReads = value }
    func holdAfterRemoval(failing: Bool) { holdAfterRemoval = true; removalFails = failing }
    func failListing(_ value: Bool) { listingFails = value }

    func finishRead(_ id: Int) {
        guard let read = held.removeValue(forKey: id) else { return }
        read.continuation.resume(returning: read.response)
    }

    func finishAll() {
        holdReads = false
        for id in pendingIDs { finishRead(id) }
    }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        calls.append(step)
        let root = step.arguments.drop(while: { $0 != "-C" }).dropFirst().first ?? "/missing"
        if step.arguments.contains("list") {
            let result = listingFails ? ProcessResult(status: 128, standardError: "fatal: repository is temporarily unavailable")
                : ProcessResult(status: 0, standardOutput: Self.porcelain(root: root, includeManaged: !removed.contains(root)))
            guard holdReads else { return result }
            let id = nextRead
            nextRead += 1
            return await withCheckedContinuation { held[id] = HeldRead(response: result, continuation: $0) }
        }
        if step.arguments.contains("remove") {
            removedFrom.append(root)
            if !removalFails { removed.insert(root) }
            if holdAfterRemoval { holdReads = true }
            return removalFails ? ProcessResult(status: 128, standardError: "fatal: worktree contains modified or untracked files") : ProcessResult(status: 0)
        }
        // git config: no hooks, filter drivers or conditional includes.
        return ProcessResult(status: 0)
    }

    private static func porcelain(root: String, includeManaged: Bool) -> String {
        var result = "worktree \(root)\0HEAD abc\0branch refs/heads/main\0\0"
        if includeManaged { result += "worktree \(root)/.right-here/worktrees/feature\0HEAD def\0branch refs/heads/feature\0\0" }
        return result
    }
}

@Suite("The setup window's worktree browser")
@MainActor
struct SetupModelWorktreeTests {
    private func seed(_ mac: Mac, roots: [URL] = [firstRoot]) {
        mac.model.apply(SetupSnapshot(folders: FolderSnapshot(repositories: roots), configFile: mac.paths.configFile, home: mac.home))
    }

    private func rows(_ model: SetupModel) throws -> [WorktreeRow] {
        guard case .loaded(let rows) = model.worktrees else {
            throw TestFailure.notLoaded
        }
        return rows
    }

    private enum TestFailure: Error { case notLoaded }

    private func waitForReads(_ runner: WorktreeRunner, count: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if await runner.pendingIDs.count == count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test func aChosenRepositoryStaysInTheSwitcherAfterReturningToAKnownRepository() async throws {
        let runner = WorktreeRunner()
        let mac = try Mac(pickFolder: { _ in secondRoot.appendingPathComponent("Sources") }, worktreeRunner: runner,
                          gitRoots: [firstRoot.path, secondRoot.path])
        defer { mac.cleanUp() }
        seed(mac)
        await mac.model.chooseRepository()
        #expect(mac.model.repository == secondRoot)
        #expect(mac.model.repositories == [firstRoot, secondRoot])
        mac.model.selectRepository(firstRoot)
        #expect(await mac.eventually { !mac.model.isLoadingWorktrees })
        #expect(mac.model.repository == firstRoot)
        #expect(mac.model.repositories == [firstRoot, secondRoot], "returning to a known repository must not forget the one just chosen")
        seed(mac, roots: [firstRoot, secondRoot])
        #expect(mac.model.repositories == [firstRoot, secondRoot], "the same root from saved folders and the picker appears once")
        #expect(!FileManager.default.fileExists(atPath: mac.paths.stateFile.path), "choosing a repository is not pinning a folder")
    }

    @Test func switchingARepositoryImmediatelyRemovesThePreviousRowsAndDropsTheirLateRead() async throws {
        let runner = WorktreeRunner()
        let mac = try Mac(worktreeRunner: runner); defer { mac.cleanUp() }
        seed(mac, roots: [firstRoot, secondRoot])
        await mac.model.refreshWorktrees()
        #expect(try rows(mac.model).first?.entry.path == firstRoot.path)
        await runner.holdReads(true)
        let older = Task { await mac.model.refreshWorktrees() }
        guard await waitForReads(runner, count: 1) else {
            await runner.finishAll(); await older.value
            Issue.record("the first read did not start"); return
        }
        mac.model.selectRepository(secondRoot)
        #expect(mac.model.worktrees == .loading)
        guard await waitForReads(runner, count: 2) else {
            await runner.finishAll(); await older.value
            Issue.record("the second read did not start"); return
        }
        await runner.finishRead(1)
        #expect(await mac.eventually { !mac.model.isLoadingWorktrees })
        await runner.finishRead(0)
        await older.value
        #expect(try rows(mac.model).first?.entry.path == secondRoot.path)
        #expect(mac.model.repository == secondRoot)
    }

    @Test func aSwitchHidesRowsBeforeItsReadTaskStarts() async throws {
        let runner = WorktreeRunner()
        let mac = try Mac(worktreeRunner: runner); defer { mac.cleanUp() }
        seed(mac, roots: [firstRoot, secondRoot])
        await mac.model.refreshWorktrees()
        let oldRow = try #require(try rows(mac.model).last)
        mac.model.selectRepository(secondRoot)
        #expect(mac.model.worktrees == .loading, "old rows must not appear under the newly selected repository")
        #expect(mac.model.removalRequest(for: oldRow) == nil)
        #expect(await mac.eventually { !mac.model.isLoadingWorktrees })
    }

    @Test func aFoldersRefreshThatChangesTheDefaultRepositoryClearsItsPreviousRows() async throws {
        let runner = WorktreeRunner()
        let mac = try Mac(worktreeRunner: runner); defer { mac.cleanUp() }
        seed(mac)
        await mac.model.refreshWorktrees()
        let previousRow = try #require(try rows(mac.model).last)
        seed(mac, roots: [secondRoot])
        #expect(mac.model.repository == secondRoot)
        #expect(mac.model.worktrees == .loading)
        #expect(mac.model.removalRequest(for: previousRow) == nil)
        await mac.model.refreshWorktrees()
        #expect(try rows(mac.model).first?.entry.path == secondRoot.path)
        seed(mac, roots: [])
        #expect(mac.model.repository == nil)
        #expect(mac.model.worktrees == .idle)
    }

    @Test func choosingAFolderReleasesTheControlsWhileItsWorktreeListLoads() async throws {
        let runner = WorktreeRunner()
        let mac = try Mac(pickFolder: { _ in secondRoot }, worktreeRunner: runner, gitRoots: [secondRoot.path])
        defer { mac.cleanUp() }
        seed(mac)
        await runner.holdReads(true)
        let choosing = Task { await mac.model.chooseRepository() }
        guard await waitForReads(runner, count: 1) else {
            await runner.finishAll(); await choosing.value
            Issue.record("the chosen repository's read did not start"); return
        }
        guard !mac.model.isWorking else {
            await runner.finishAll(); await choosing.value
            Issue.record("the chooser kept every control disabled while git was only reading"); return
        }
        await choosing.value
        #expect(mac.model.isLoadingWorktrees)
        mac.model.selectRepository(firstRoot)
        #expect(mac.model.repository == firstRoot)
        await runner.finishAll()
        #expect(await mac.eventually { !mac.model.isLoadingWorktrees })
        #expect(try rows(mac.model).first?.entry.path == firstRoot.path)
    }

    @Test func retryReadsTheSelectedRepositoryAndReplacesItsError() async throws {
        let runner = WorktreeRunner()
        let mac = try Mac(worktreeRunner: runner); defer { mac.cleanUp() }
        seed(mac)
        await runner.failListing(true)
        await mac.model.refreshWorktrees()
        guard case .failed(let text) = mac.model.worktrees else { Issue.record("no error was shown"); return }
        #expect(text.contains("temporarily unavailable"))
        await runner.failListing(false)
        await mac.model.refreshWorktrees()
        #expect(try rows(mac.model).count == 2)
        #expect(mac.model.repository == firstRoot)
    }

    @Test func aRemovalUsesTheRepositoryNamedWhenItsConfirmationWasOpened() async throws {
        let runner = WorktreeRunner()
        let mac = try Mac(worktreeRunner: runner); defer { mac.cleanUp() }
        seed(mac, roots: [firstRoot, secondRoot])
        await mac.model.refreshWorktrees()
        let row = try #require(try rows(mac.model).last)
        let request = try #require(mac.model.removalRequest(for: row))
        mac.model.selectRepository(secondRoot)
        #expect(await mac.eventually { !mac.model.isLoadingWorktrees })
        await mac.model.remove(request)
        #expect(await runner.removedFrom == [firstRoot.path])
        #expect(mac.model.notice == .worktreeRemoved(row.entry.path))
        #expect(mac.model.repository == secondRoot)
        #expect(try rows(mac.model).count == 2)
        #expect(try rows(mac.model).first?.entry.path == secondRoot.path)
    }

    @Test(arguments: [false, true])
    func removalKeepsControlsBusyUntilItsNewListIsVisible(failing: Bool) async throws {
        let runner = WorktreeRunner()
        let mac = try Mac(worktreeRunner: runner); defer { mac.cleanUp() }
        seed(mac, roots: [firstRoot, secondRoot])
        await mac.model.refreshWorktrees()
        let row = try #require(try rows(mac.model).last)
        let request = try #require(mac.model.removalRequest(for: row))
        await runner.holdAfterRemoval(failing: failing)
        let removing = Task { await mac.model.remove(request) }
        guard await waitForReads(runner, count: 1) else {
            await runner.finishAll(); await removing.value
            Issue.record("the final read did not start"); return
        }
        guard mac.model.isWorking else {
            await runner.finishAll(); await removing.value
            Issue.record("worktree controls became available before the final list arrived"); return
        }
        mac.model.selectRepository(secondRoot)
        await mac.model.remove(request)
        await mac.model.refreshWorktrees()
        #expect(mac.model.repository == firstRoot)
        #expect(await runner.removedFrom == [firstRoot.path])
        #expect(await runner.pendingIDs.count == 1)
        await runner.finishRead(0)
        await removing.value
        #expect(!mac.model.isWorking)
        #expect(try rows(mac.model).count == (failing ? 2 : 1))
        #expect(mac.model.notice?.isProblem == failing)
    }

    @Test func aRowThatIsNotInTheCurrentListCannotOpenARemovalConfirmation() async throws {
        let runner = WorktreeRunner()
        let mac = try Mac(worktreeRunner: runner); defer { mac.cleanUp() }
        seed(mac)
        await mac.model.refreshWorktrees()
        let main = try #require(try rows(mac.model).first)
        #expect(mac.model.removalRequest(for: main) == nil)
        let missing = WorktreeRow(entry: WorktreeEntry(path: "/work/other", head: "abc", branch: "other"), isMainWorkingCopy: false, canBeRemoved: true)
        #expect(mac.model.removalRequest(for: missing) == nil)
        #expect(await runner.removedFrom.isEmpty)
    }
}
