import Foundation
import Testing
import RightHereCore
import RightHereKit
@testable import AppModel

/// Each list captures git's answer before a test releases it. No process or application is started.
private actor WorktreeRunner: ProcessRunner {
    private struct Read {
        let answer: ProcessResult
        let continuation: CheckedContinuation<ProcessResult, Never>
    }

    private var held: [Int: Read] = [:]
    private var nextRead = 0
    private var holdReads = false
    private var holdAfterRemoval = false
    private var removalFails = false
    private var listingFails = false
    private var removed = Set<String>()
    private var ignored: [String] = []
    private(set) var calls: [ProcessStep] = []
    private(set) var removedFrom: [String] = []

    var pendingIDs: [Int] { held.keys.sorted() }
    func holdReads(_ hold: Bool) { holdReads = hold }
    func holdAfterRemoval(failing: Bool) { holdAfterRemoval = true; removalFails = failing }
    func failListing(_ fail: Bool) { listingFails = fail }
    func ignoredFiles(_ files: [String]) { ignored = files }

    func finishRead(_ id: Int) {
        guard let read = held.removeValue(forKey: id) else { return }
        read.continuation.resume(returning: read.answer)
    }

    func finishAll() {
        holdReads = false
        for id in pendingIDs { finishRead(id) }
    }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        calls.append(step)
        let root = step.arguments.drop(while: { $0 != "-C" }).dropFirst().first ?? "/missing"
        if step.arguments.contains("list") {
            var text = "worktree \(root)\0HEAD abc\0branch refs/heads/main\0\0"
            if !removed.contains(root) { text += "worktree \(root)/.right-here/worktrees/feature\0HEAD def\0branch refs/heads/feature\0\0" }
            let answer = listingFails ? ProcessResult(status: 128, standardError: "fatal: repository is temporarily unavailable") : ProcessResult(status: 0, standardOutput: text)
            guard holdReads else { return answer }
            let id = nextRead
            nextRead += 1
            return await withCheckedContinuation { held[id] = Read(answer: answer, continuation: $0) }
        }
        if step.arguments.contains("remove") {
            removedFrom.append(root)
            if !removalFails { removed.insert(root) }
            if holdAfterRemoval { holdReads = true }
            return removalFails ? ProcessResult(status: 128, standardError: "fatal: worktree contains modified files") : ProcessResult(status: 0)
        }
        if step.arguments.contains("status") { return ProcessResult(status: 0, standardOutput: ignored.map { "!! \($0)\0" }.joined()) }
        // git config finds no hooks, drivers or conditional includes.
        return ProcessResult(status: 1)
    }
}

@MainActor
private struct WorktreeMac {
    let home: URL
    let paths: RHPaths
    let first: URL
    let second: URL
    let model: SetupModel
    let runner: WorktreeRunner

    init() throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
        first = home.appendingPathComponent("first")
        second = home.appendingPathComponent("second")
        for root in [first, second] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".right-here/worktrees/feature"), withIntermediateDirectories: true)
        }
        runner = WorktreeRunner()
        let facts = FakeSystemFacts(homeDirectory: home)
        let helper = "/Applications/Right Here.app/Contents/Helpers/rh"
        model = SetupModel(loader: SetupLoader(facts: facts, paths: paths, runner: FakeProcessRunner(), helperPath: helper),
                           actions: SetupActions(facts: facts, paths: paths, runner: FakeProcessRunner(), helperPath: helper, trialHome: home),
                           facts: facts, helper: helper, worktreeBrowser: WorktreeBrowser(runner: runner))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }
    func seed(_ roots: [URL]) {
        model.apply(SetupSnapshot(folders: FolderSnapshot(repositories: roots), configFile: paths.configFile, home: home))
    }

    func rows() throws -> [WorktreeRow] {
        guard case .loaded(let rows) = model.worktrees else { throw NotLoaded.list }
        return rows
    }

    private enum NotLoaded: Error { case list }

    func waitForReads(_ count: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if await runner.pendingIDs.count == count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func waitForList() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if case .loaded = model.worktrees { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

@Suite("The setup window's worktree context")
@MainActor
struct SetupModelWorktreeTests {
    @Test func manuallyChosenRepositoriesRemainAvailableWithoutPinningThem() async throws {
        let mac = try WorktreeMac(); defer { mac.cleanUp() }
        mac.seed([mac.first])
        mac.model.selectRepository(mac.second)
        #expect(await mac.waitForList())
        #expect(mac.model.repositories == [mac.first, mac.second])
        mac.model.selectRepository(mac.first)
        #expect(await mac.waitForList())
        #expect(mac.model.repositories == [mac.first, mac.second])
        mac.seed([mac.first, mac.second])
        #expect(mac.model.repositories == [mac.first, mac.second])
        #expect(!FileManager.default.fileExists(atPath: mac.paths.stateFile.path))
    }

    @Test func changingRepositoryClearsRowsBeforeTheReadTaskCanStart() async throws {
        let mac = try WorktreeMac(); defer { mac.cleanUp() }
        mac.seed([mac.first, mac.second])
        await mac.model.refreshWorktrees()
        #expect(try mac.rows().first?.entry.path == mac.first.path)
        let previousRow = try #require(try mac.rows().last)
        mac.model.selectRepository(mac.second)
        #expect(mac.model.worktrees == .loading)
        #expect(mac.model.removalRequest(for: previousRow) == nil)
        #expect(await mac.waitForList())
        #expect(try mac.rows().first?.entry.path == mac.second.path)
    }

    @Test func savedFoldersChangingTheDefaultRepositoryInvalidateItsOldRowsImmediately() async throws {
        let mac = try WorktreeMac(); defer { mac.cleanUp() }
        mac.seed([mac.first])
        await mac.model.refreshWorktrees()
        mac.seed([mac.second])
        #expect(mac.model.repository == mac.second)
        #expect(mac.model.worktrees == .loading)
        await mac.model.refreshWorktrees()
        #expect(try mac.rows().first?.entry.path == mac.second.path)
        mac.seed([])
        #expect(mac.model.repository == nil)
        #expect(mac.model.worktrees == .idle)
    }

    @Test func switchingRepositoriesDropsAReadThatFinishesLate() async throws {
        let mac = try WorktreeMac(); defer { mac.cleanUp() }
        mac.seed([mac.first, mac.second])
        await mac.runner.holdReads(true)
        let older = Task { await mac.model.refreshWorktrees() }
        guard await mac.waitForReads(1) else { await mac.runner.finishAll(); await older.value; Issue.record("first read did not start"); return }
        mac.model.selectRepository(mac.second)
        guard await mac.waitForReads(2) else { await mac.runner.finishAll(); await older.value; Issue.record("second read did not start"); return }
        await mac.runner.finishRead(1)
        #expect(await mac.waitForList())
        await mac.runner.finishRead(0)
        await older.value
        #expect(try mac.rows().first?.entry.path == mac.second.path)
    }

    @Test func readFailureCanBeRetriedWithoutChangingRepositoryOrRemovingAnything() async throws {
        let mac = try WorktreeMac(); defer { mac.cleanUp() }
        mac.seed([mac.first])
        await mac.runner.failListing(true)
        await mac.model.refreshWorktrees()
        guard case .failed(let sentences) = mac.model.worktrees else { Issue.record("no error shown"); return }
        #expect(Localizer.english.render(sentences: sentences).contains("temporarily unavailable"))
        await mac.runner.failListing(false)
        await mac.model.refreshWorktrees()
        #expect(try mac.rows().count == 2)
        #expect(mac.model.repository == mac.first)
        #expect(await mac.runner.removedFrom.isEmpty)
    }

    @Test(arguments: [false, true])
    func removalKeepsTheRepositoryLockedUntilItsFinalReadFinishes(failing: Bool) async throws {
        let mac = try WorktreeMac(); defer { mac.cleanUp() }
        mac.seed([mac.first, mac.second])
        await mac.model.refreshWorktrees()
        let row = try #require(try mac.rows().last)
        let request = try #require(mac.model.removalRequest(for: row))
        await mac.runner.holdAfterRemoval(failing: failing)
        let removing = Task { await mac.model.remove(request) }
        guard await mac.waitForReads(1) else { await mac.runner.finishAll(); await removing.value; Issue.record("final read did not start"); return }
        guard mac.model.isWorking else {
            await mac.runner.finishAll(); await removing.value
            Issue.record("controls became available before the updated list arrived"); return
        }
        mac.model.selectRepository(mac.second)
        #expect(mac.model.repository == mac.first)
        await mac.model.remove(request)
        #expect(await mac.runner.removedFrom == [mac.first.path])
        await mac.model.refreshWorktrees()
        #expect(await mac.runner.pendingIDs.count == 1)
        await mac.runner.finishAll()
        await removing.value
        #expect(!mac.model.isWorking)
        #expect(try mac.rows().count == (failing ? 2 : 1))
        #expect(mac.model.notice?.isProblem == failing)
    }

    @Test func removalUsesTheRepositoryWhoseRowWasConfirmed() async throws {
        let mac = try WorktreeMac(); defer { mac.cleanUp() }
        mac.seed([mac.first, mac.second])
        await mac.model.refreshWorktrees()
        let row = try #require(try mac.rows().last)
        let request = try #require(mac.model.removalRequest(for: row))
        mac.model.selectRepository(mac.second)
        await mac.model.refreshWorktrees()
        await mac.model.remove(request)
        #expect(await mac.runner.removedFrom == [mac.first.path])
        #expect(mac.model.repository == mac.second)
        #expect(try mac.rows().first?.entry.path == mac.second.path)
        #expect(try mac.rows().count == 2)
    }

    @Test func ignoredFilesStayAttachedToTheirRepositoryAndAskAgainForNewFiles() async throws {
        let mac = try WorktreeMac(); defer { mac.cleanUp() }
        mac.seed([mac.first, mac.second])
        await mac.model.refreshWorktrees()
        let row = try #require(try mac.rows().last)
        let request = try #require(mac.model.removalRequest(for: row))
        await mac.runner.ignoredFiles([".env"])
        await mac.model.remove(request)
        let held = try #require(mac.model.pendingIgnoredRemoval)
        #expect(held.files == [".env"])
        #expect(held.request == request)
        mac.model.selectRepository(mac.second)
        #expect(mac.model.repository == mac.first, "the second confirmation still describes the first repository")
        await mac.runner.ignoredFiles([".env", ".secret"])
        await mac.model.confirmIgnoredRemoval(held)
        guard let again = mac.model.pendingIgnoredRemoval else {
            Issue.record("a newly ignored file was not presented for agreement"); return
        }
        #expect(again.files == [".env", ".secret"])
        #expect(again.request == request)
        #expect(await mac.runner.removedFrom.isEmpty)
        await mac.model.confirmIgnoredRemoval(again)
        #expect(await mac.runner.removedFrom == [mac.first.path])
        #expect(mac.model.pendingIgnoredRemoval == nil)
        let removes = await mac.runner.calls.filter { $0.arguments.contains("remove") }
        #expect(removes.count == 1 && !removes.contains { $0.arguments.contains("--force") })
        #expect(!(await mac.runner.calls).contains { $0.arguments.contains("branch") })
    }

    @Test func aMissingOrProtectedRowCannotOpenARemovalQuestion() async throws {
        let mac = try WorktreeMac(); defer { mac.cleanUp() }
        mac.seed([mac.first])
        await mac.model.refreshWorktrees()
        let main = try #require(try mac.rows().first)
        #expect(mac.model.removalRequest(for: main) == nil)
        let foreign = WorktreeRow(entry: WorktreeEntry(path: mac.second.appendingPathComponent(".right-here/worktrees/feature").path, head: "abc", branch: "feature"),
                                  isMainWorkingCopy: false, canBeRemoved: true)
        #expect(mac.model.removalRequest(for: foreign) == nil)
        #expect(await mac.runner.removedFrom.isEmpty)
    }
}
