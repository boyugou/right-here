import Foundation
import Synchronization
import Testing
import RightHereCore
@testable import RightHereKit

// What every git command carries, written out in full and not asked of `GitCommand`: when one override is dropped from one command, that
// command's vector no longer equals what is written here.

/// Hooks and the file system monitor off, no lazy fetch: what a command carries when no filter driver is blanked.
private let guarded: [String: String] = [
    "GIT_NO_LAZY_FETCH": "1", "GIT_NO_REPLACE_OBJECTS": "1", "GIT_CONFIG_COUNT": "2",
    "GIT_CONFIG_KEY_0": "core.hooksPath", "GIT_CONFIG_VALUE_0": "/dev/null",
    "GIT_CONFIG_KEY_1": "core.fsmonitor", "GIT_CONFIG_VALUE_1": "false"
]

/// The same with the hook `linter` of the configuration switched off.
private let guardedAgainstLinter: [String: String] = guarded.merging([
    "GIT_CONFIG_COUNT": "3", "GIT_CONFIG_KEY_2": "hook.linter.enabled", "GIT_CONFIG_VALUE_2": "false"
]) { $1 }

/// The same with the driver `evil` blanked too.
private let guardedAgainstEvil: [String: String] = guarded.merging([
    "GIT_CONFIG_COUNT": "6",
    "GIT_CONFIG_KEY_2": "filter.evil.smudge", "GIT_CONFIG_VALUE_2": "",
    "GIT_CONFIG_KEY_3": "filter.evil.clean", "GIT_CONFIG_VALUE_3": "",
    "GIT_CONFIG_KEY_4": "filter.evil.process", "GIT_CONFIG_VALUE_4": "",
    "GIT_CONFIG_KEY_5": "filter.evil.required", "GIT_CONFIG_VALUE_5": "false"
]) { $1 }

/// What the environment `rh` was started with must not give git: a repository, an index or settings other than the one `-C` names.
private let inherited = ["GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
                         "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG"]

private func git(_ arguments: [String], environment: [String: String] = guarded) -> ProcessStep {
    ProcessStep(executable: "/usr/bin/git", arguments: ["--no-pager"] + arguments, environment: environment, unsetEnvironment: inherited)
}

private func listingOfDefinitions(in directory: String) -> ProcessStep {
    git(["-C", directory, "config", "-z", "--show-scope", "--name-only", "--get-regexp", "^(filter|hook|includeif)\\."])
}

private let root = URL(fileURLWithPath: "/work/app")
private let worktree = "/work/app/.right-here/worktrees/feature"
private let listedWithTheWorktree = porcelainZ("worktree /work/app\nHEAD aaaa\nbranch refs/heads/main\n\nworktree \(worktree)\nHEAD bbbb\nbranch refs/heads/feature\n")

/// The first suite looks at the whole command (program, every argument, the whole environment) of each git command that Right Here runs, with a runner
/// that only records. The second runs the real git against a repository that tries to start something of its own.
@Suite("git guard: the commands")
struct GitGuardCommandTests {
    @Test func listingTheWorktreesCarriesTheGuards() async throws {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: listedWithTheWorktree)])
        _ = try await GitWorktreeManager.listWorktrees(in: root, runner: runner)
        #expect(runner.recorded == [git(["-C", "/work/app", "worktree", "list", "--porcelain", "-z"])])
    }

    @Test func makingAWorktreeAsksWhatTheRepositoryDefinesAndThenAddsWithEveryOverride() async throws {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 1), ProcessResult(status: 0)])
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: root, branch: "feature", runner: runner)
        #expect(made.wasCreated && made.branchCreated)
        #expect(runner.recorded == [
            listingOfDefinitions(in: "/work/app"),
            git(["-C", "/work/app", "worktree", "add", "-b", "feature", worktree, "HEAD"])
        ])
    }

    @Test func aDriverTheRepositoryDefinesIsBlankedInBothFormsOfTheAdd() async throws {
        let listing = "local\0filter.evil.smudge\0local\0filter.evil.clean\0"
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: listing), ProcessResult(status: 128, standardError: "fatal: a branch named 'feature' already exists"), ProcessResult(status: 0)])
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: root, branch: "feature", runner: runner)
        #expect(made.wasCreated && !made.branchCreated)
        #expect(runner.recorded == [
            listingOfDefinitions(in: "/work/app"),
            git(["-C", "/work/app", "worktree", "add", "-b", "feature", worktree, "HEAD"], environment: guardedAgainstEvil),
            git(["-C", "/work/app", "worktree", "add", "--", worktree, "feature"], environment: guardedAgainstEvil)
        ])
    }

    @Test func theStatusOfAnUnusedWorktreeCarriesTheGuardsAndWhatItsOwnConfigurationDefines() async {
        let created = WorktreeResult(branch: "feature", worktreeURL: URL(fileURLWithPath: worktree), wasCreated: true, branchCreated: true)
        let runner = FakeProcessRunner(results: [
            ProcessResult(status: 0, standardOutput: "worktree\0filter.evil.clean\0"), ProcessResult(status: 0, standardOutput: ""),
            ProcessResult(status: 0, standardOutput: listedWithTheWorktree), ProcessResult(status: 1), ProcessResult(status: 0), ProcessResult(status: 0)
        ])
        #expect(await GitWorktreeManager.discardIfUnchanged(created, gitRoot: root, runner: runner))
        #expect(runner.recorded == [
            listingOfDefinitions(in: worktree),
            git(["-C", worktree, "status", "--porcelain", "--untracked-files=all"], environment: guardedAgainstEvil),
            git(["-C", "/work/app", "worktree", "list", "--porcelain", "-z"]),
            listingOfDefinitions(in: "/work/app"),
            git(["-C", "/work/app", "worktree", "remove", "--", worktree]),
            git(["-C", "/work/app", "branch", "-d", "--", "feature"])
        ])
    }

    @Test func removingAWorktreeAsksWhatTheRepositoryDefinesAndCarriesTheGuardsOnTheRemovalAndOnTheBranch() async throws {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: listedWithTheWorktree), ProcessResult(status: 0, standardOutput: "local\0filter.evil.process\0"), ProcessResult(status: 0), ProcessResult(status: 0)])
        let removal = try await GitWorktreeManager.removeWorktree(worktreePath: "feature", gitRoot: root, deleteBranch: true, runner: runner)
        #expect(removal.branchDeleted)
        #expect(runner.recorded == [
            git(["-C", "/work/app", "worktree", "list", "--porcelain", "-z"]),
            listingOfDefinitions(in: "/work/app"),
            git(["-C", "/work/app", "worktree", "remove", "--", worktree], environment: guardedAgainstEvil),
            git(["-C", "/work/app", "branch", "-d", "--", "feature"], environment: guardedAgainstEvil)
        ])
    }

    @Test func aConditionalIncludeOfTheRepositoryIsRefusedBeforeAnythingIsAddedAndThePersonsOwnIsNot() async throws {
        let refused = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "local\0includeif.onbranch:rh/**.path\0")])
        await #expect(throws: WorktreeError.conditionalInclude("onbranch:rh/**")) {
            _ = try await GitWorktreeManager.prepareWorktree(gitRoot: root, branch: "feature", runner: refused)
        }
        #expect(refused.recorded == [listingOfDefinitions(in: "/work/app")], "nothing but the question was asked")
        // An include of the person's own configuration (an identity for the folder they work in) is theirs, and the same in every worktree.
        let own = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "global\0includeif.gitdir:~/work/.path\0command\0includeif.onbranch:x.path\0"), ProcessResult(status: 0)])
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: root, branch: "feature", runner: own)
        #expect(made.wasCreated)
        #expect(own.recorded.last == git(["-C", "/work/app", "worktree", "add", "-b", "feature", worktree, "HEAD"]))
    }

    @Test func aHookTheConfigurationDefinesIsSwitchedOffWhatEverTheScopeAndOnEveryCommandThatCanRunOne() async throws {
        let listing = "global\0hook.linter.event\0global\0hook.linter.command\0local\0hook.jobs\0"
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: listing), ProcessResult(status: 0)])
        _ = try await GitWorktreeManager.prepareWorktree(gitRoot: root, branch: "feature", runner: runner)
        #expect(runner.recorded.last == git(["-C", "/work/app", "worktree", "add", "-b", "feature", worktree, "HEAD"], environment: guardedAgainstLinter))

        let removing = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: listedWithTheWorktree), ProcessResult(status: 0, standardOutput: listing), ProcessResult(status: 0), ProcessResult(status: 0)])
        _ = try await GitWorktreeManager.removeWorktree(worktreePath: "feature", gitRoot: root, deleteBranch: true, runner: removing)
        #expect(removing.recorded.suffix(2) == [git(["-C", "/work/app", "worktree", "remove", "--", worktree], environment: guardedAgainstLinter),
                                               git(["-C", "/work/app", "branch", "-d", "--", "feature"], environment: guardedAgainstLinter)])
    }

    @Test func aForcedRemovalPassesForceAndNothingElseIsDifferent() async throws {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: listedWithTheWorktree), ProcessResult(status: 1), ProcessResult(status: 0)])
        _ = try await GitWorktreeManager.removeWorktree(worktreePath: worktree, gitRoot: root, force: true, runner: runner)
        #expect(runner.recorded.last == git(["-C", "/work/app", "worktree", "remove", "--force", "--", worktree]))
    }

    @Test func whatTheRepositoryDefinesIsLookedForInTheWorktreeBeingRemovedAsWellWhenItIsThere() async throws {
        let repository = try makeTemporaryDirectory().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: repository) }
        let folder = repository.appendingPathComponent(".right-here/worktrees/feature")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let listed = porcelainZ("worktree \(repository.path)\nHEAD aaaa\nbranch refs/heads/main\n\nworktree \(folder.path)\nHEAD bbbb\nbranch refs/heads/feature\n")
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: listed), ProcessResult(status: 1), ProcessResult(status: 0, standardOutput: "worktree\0filter.evil.clean\0"), ProcessResult(status: 0)])
        _ = try await GitWorktreeManager.removeWorktree(worktreePath: "feature", gitRoot: repository, runner: runner)
        // `git worktree remove` runs its status inside the worktree, with that worktree's configuration (its `config.worktree` is not the main folder's).
        #expect(runner.recorded[1] == listingOfDefinitions(in: repository.path))
        #expect(runner.recorded[2] == listingOfDefinitions(in: folder.path))
        #expect(runner.recorded[3] == git(["-C", repository.path, "worktree", "remove", "--", folder.path], environment: guardedAgainstEvil))
    }

    @Test func aFailingListingOfWhatTheRepositoryDefinesStopsTheCommand() async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 128, standardError: "fatal: detected dubious ownership in repository")])
        await #expect(throws: ExecutionError.self) { _ = try await GitWorktreeManager.prepareWorktree(gitRoot: root, branch: "feature", runner: runner) }
        #expect(runner.recorded.count == 1, "nothing was added after the definitions could not be listed")
    }

    // MARK: Time limits

    @Test func everyCommandThatOnlyReadsIsGivenATimeLimitAndOneThatTimesOutSaysSo() async throws {
        let runner = LimitRecordingRunner(results: [ProcessResult(status: 0, standardOutput: listedWithTheWorktree), ProcessResult(status: 1), ProcessResult(status: 0), ProcessResult(status: 0)])
        _ = try await GitWorktreeManager.removeWorktree(worktreePath: "feature", gitRoot: root, deleteBranch: true, runner: runner)
        // The list, the definitions and `branch -d` are read-only; the removal itself is real work and is not cut short.
        #expect(runner.limits == [.seconds(20), .seconds(20), nil, .seconds(20)])

        let stuck = LimitRecordingRunner(results: [ProcessResult(status: 143, terminatedAfter: .seconds(20))])
        await #expect(throws: ExecutionError.timedOut(step: "git worktree list", seconds: 20)) { _ = try await GitWorktreeManager.listWorktrees(in: root, runner: stuck) }
        let stuckListing = LimitRecordingRunner(results: [ProcessResult(status: 143, terminatedAfter: .seconds(20))])
        await #expect(throws: ExecutionError.timedOut(step: "git config", seconds: 20)) { _ = try await GitCommand.defined(in: "/work/app", runner: stuckListing) }
    }

    @Test func theStatusThatDecidesWhetherAnUnusedWorktreeIsDiscardedHasATimeLimitToo() async {
        // `git status` runs the clean filter of every file whose dates changed: a hung one must not hold the request for ever.
        let created = WorktreeResult(branch: "feature", worktreeURL: URL(fileURLWithPath: worktree), wasCreated: true, branchCreated: true)
        let runner = LimitRecordingRunner(results: [ProcessResult(status: 0, standardOutput: ""), ProcessResult(status: 0, standardOutput: " M file\n")])
        #expect(await GitWorktreeManager.discardIfUnchanged(created, gitRoot: root, runner: runner) == false, "a worktree with a change is kept")
        #expect(runner.limits == [.seconds(20), .seconds(20)], "\(runner.limits)")
    }

    // MARK: What the repository defines

    private func defined(_ listing: String) async throws -> GitCommand.Defined {
        try await GitCommand.defined(in: "/work/app", runner: FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: listing)]))
    }

    @Test func theDriversOfTheRepositoryAreBlankedWhicheverFileDefinesThemAndThePersonsOwnAreKept() async throws {
        let listing = ["global", "filter.lfs.clean", "global", "filter.lfs.smudge", "system", "filter.sys.process", "command", "filter.cmd.smudge",
                       "local", "filter.evil.smudge", "local", "filter.evil.clean", "worktree", "filter.fromworktree.process", "includeprobe", "filter.fromthefuture.clean", ""].joined(separator: "\0")
        #expect(try await defined(listing).filterDrivers == ["evil", "fromthefuture", "fromworktree"])
    }

    @Test func aDriversNameIsEverythingBetweenTheFirstAndTheLastDot() async throws {
        let listing = ["local", "filter.a=b.smudge", "local", "filter.dot.ted.clean", "local", "filter.tab\there.process", "local", "filter.\u{301}mark.smudge",
                       "local", "filter..clean", "local", "filter.UPPER.required", "local", "filter.smudge", ""].joined(separator: "\0")
        #expect(try await defined(listing).filterDrivers == ["", "UPPER", "a=b", "dot.ted", "tab\there", "\u{301}mark"])
    }

    @Test func everyHookTheConfigurationNamesIsFoundWhateverTheScopeAndASettingWithoutANameIsNotOne() async throws {
        let listing = ["global", "hook.mine.event", "global", "hook.mine.command", "local", "hook.evil.event", "worktree", "hook.a=b.command", "local", "hook.dot.ted.event",
                       "local", "hook.jobs", "local", "hook.pre-commit.parallel", ""].joined(separator: "\0")
        #expect(try await defined(listing).hooks == ["a=b", "dot.ted", "evil", "mine", "pre-commit"])
    }

    @Test func noDefinitionsIsNoDefinitions() async throws {
        #expect(try await defined("") == GitCommand.Defined())
        #expect(try await defined("global\0filter.lfs.clean\0") == GitCommand.Defined())
    }

    @Test func aSettingOfAnotherSectionIsNotTaken() async throws {
        #expect(try await defined("local\0core.hooksPath\0local\0filters.evil.clean\0local\0xfilter.evil.clean\0") == GitCommand.Defined())
    }
}

// MARK: The real git

/// Whether the git on this Mac is 2.54 or later, which is when a hook can be a command named in the configuration. The git of Xcode 26 is older, and a test of
/// that kind of hook (its control above all: "git without the guards runs it") means nothing there.
private let gitKnowsConfigHooks: Bool = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["--version"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    // "git version 2.54.0" or "git version 2.50.1 (Apple Git-155)".
    let numbers = String(decoding: data, as: UTF8.self).split(separator: " ").dropFirst(2).first?.split(separator: ".").compactMap { Int($0) } ?? []
    guard numbers.count >= 2 else { return false }
    return (numbers[0], numbers[1]) >= (2, 54)
}()

/// A git that reads nothing of the person's: a global configuration of its own, no system one, no prompts. Everything lives in one folder.
private final class Lab {
    let folder: URL
    let repository: URL
    let outside: URL

    init() throws {
        folder = try makeTemporaryDirectory().resolvingSymlinksInPath()
        repository = folder.appendingPathComponent("repository")
        outside = folder.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "[user]\n\tname = Test\n\temail = test\n[commit]\n\tgpgsign = false\n[init]\n\tdefaultBranch = main\n".write(to: globalConfiguration, atomically: true, encoding: .utf8)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    var globalConfiguration: URL { folder.appendingPathComponent("global-gitconfig") }

    var environment: [String: String] {
        ["HOME": folder.path, "GIT_CONFIG_GLOBAL": globalConfiguration.path, "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0"]
    }

    /// The runner the code under test gets: the real one, with that environment added.
    var runner: any ProcessRunner { EnvironmentRunner(base: LiveProcessRunner(), adding: environment) }

    @discardableResult
    func git(_ arguments: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", (directory ?? repository).path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errors = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LabError(text: "git \(arguments.joined(separator: " ")) failed: \(String(decoding: errors, as: UTF8.self))")
        }
        return String(decoding: data, as: UTF8.self)
    }

    func makeRepository(attributes: String? = "* filter=evil\n") throws {
        try git(["init", "-q"])
        try "initial".write(to: repository.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git(["add", "README.md"])
        if let attributes {
            try attributes.write(to: repository.appendingPathComponent(".gitattributes"), atomically: true, encoding: .utf8)
            try git(["add", ".gitattributes"])
        }
        try git(["commit", "-q", "-m", "initial"])
    }

    /// A program that records that it ran by making `marker`. A filter has to pass its input through, a hook and a monitor must not wait for any.
    func program(_ name: String, passingInput: Bool = false) throws -> (path: String, ran: () -> Bool) {
        let marker = outside.appendingPathComponent("\(name).ran")
        let script = outside.appendingPathComponent("\(name).sh")
        try "#!/bin/sh\ntouch '\(marker.path)'\n\(passingInput ? "cat\n" : "exit 0\n")".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script.path, { FileManager.default.fileExists(atPath: marker.path) })
    }

    /// Makes the files of a worktree look as if they were written after its index: git compares such a file with the index by reading it (through the clean filter), which it
    /// otherwise does only for a file whose date is in the second of the index's own, and a test must not depend on how fast the checkout was.
    func makeLookRecentlyWritten(_ worktree: URL) throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: worktree.path) where name != ".git" {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)], ofItemAtPath: worktree.appendingPathComponent(name).path)
        }
    }
}

private struct LabError: Error, CustomStringConvertible {
    var text: String
    var description: String { text }
}

/// Adds variables to what a step runs with; the step's own win.
private struct EnvironmentRunner: ProcessRunner {
    let base: any ProcessRunner
    let adding: [String: String]

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        var step = step
        step.environment.merge(adding) { own, _ in own }
        return try await base.run(step, timeout: timeout)
    }
}

/// Records the time limit each command was given, and answers from a script.
private final class LimitRecordingRunner: ProcessRunner, Sendable {
    private struct State {
        var limits: [Duration?] = []
        var results: [ProcessResult]
    }

    private let state: Mutex<State>

    init(results: [ProcessResult]) { state = Mutex(State(results: results)) }

    var limits: [Duration?] { state.withLock { $0.limits } }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        state.withLock {
            $0.limits.append(timeout)
            return $0.results.isEmpty ? ProcessResult(status: 0) : $0.results.removeFirst()
        }
    }
}

/// Makes every time limit one second, so that a command that hangs is stopped quickly; a command without a limit is refused.
private struct ImpatientRunner: ProcessRunner {
    let base: any ProcessRunner

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        guard timeout != nil else {
            Issue.record("a command that can wait for ever was started without a time limit: \(step.arguments)")
            return ProcessResult(status: 1)
        }
        return try await base.run(step, timeout: .seconds(1))
    }
}

/// The repository tries to start programs of its own, in every way git has; each test runs one such way against the commands Right Here runs, with
/// a control that the very same repository does start it for a git without the guards, so that a test cannot pass because the trap never worked.
@Suite("git guard: the repository's own code stays quiet")
struct GitGuardRepositoryTests {
    @Test func theRepositorysFsmonitorProgramDoesNotRunWhileAWorktreeIsMade() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        let monitor = try lab.program("monitor")
        try lab.git(["config", "--local", "core.fsmonitor", monitor.path])
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner)
        #expect(made.wasCreated)
        #expect(!monitor.ran(), "the repository's core.fsmonitor program ran while the worktree was made")
        try lab.git(["worktree", "add", "-q", "-b", "control", lab.folder.appendingPathComponent("control").path])
        #expect(monitor.ran(), "control: git without the guards runs the monitor, so this test can see it")
    }

    @Test func theRepositorysHooksDoNotRunWhileAWorktreeIsMade() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        let hook = try lab.program("hook")
        for name in ["post-checkout", "reference-transaction", "post-index-change"] {
            try FileManager.default.copyItem(atPath: hook.path, toPath: lab.repository.appendingPathComponent(".git/hooks/\(name)").path)
        }
        _ = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner)
        #expect(!hook.ran(), "a hook of the repository ran while the worktree was made")
        try lab.git(["worktree", "add", "-q", "-b", "control", lab.folder.appendingPathComponent("control").path])
        #expect(hook.ran(), "control: git without the guards runs the hooks")
    }

    /// Since git 2.54 a hook can be a command named in the configuration (`hook.<name>.event`, `hook.<name>.command`), and `core.hooksPath=/dev/null` does not stop those.
    @Test(.enabled(if: gitKnowsConfigHooks, "needs git 2.54 or later: a hook named in the configuration"))
    func aHookTheConfigurationNamesDoesNotRunWhileAWorktreeIsMadeOrRemoved() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        let hook = try lab.program("configured")
        try lab.git(["config", "--local", "hook.evil.command", hook.path])
        for event in ["post-checkout", "reference-transaction", "post-index-change"] { try lab.git(["config", "--local", "--add", "hook.evil.event", event]) }
        // A second one in a file that the configuration includes, with a name that has an equals sign; and one of the person's own, which is switched off as well.
        try "[hook \"a=b\"]\n\tevent = post-checkout\n\tcommand = \(hook.path)\n".write(to: lab.repository.appendingPathComponent(".git/extra.cfg"), atomically: true, encoding: .utf8)
        try lab.git(["config", "--local", "include.path", "extra.cfg"])
        try lab.git(["config", "--global", "hook.mine.command", hook.path])
        try lab.git(["config", "--global", "hook.mine.event", "post-checkout"])

        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner)
        #expect(made.wasCreated)
        #expect(!hook.ran(), "a hook named in the configuration ran while the worktree was made")
        _ = try await GitWorktreeManager.removeWorktree(worktreePath: "isolated", gitRoot: lab.repository, deleteBranch: true, runner: lab.runner)
        #expect(!hook.ran(), "a hook named in the configuration ran while the worktree was removed")
        try lab.git(["worktree", "add", "-q", "-b", "control", lab.folder.appendingPathComponent("control").path])
        #expect(hook.ran(), "control: git without the guards runs the hooks of the configuration")
    }

    @Test func aFilterTheRepositoryDefinesDoesNotRunWhileAWorktreeIsMade() async throws {
        let lab = try Lab()
        try lab.makeRepository()
        let filter = try lab.program("smudge", passingInput: true)
        try lab.git(["config", "--local", "filter.evil.smudge", filter.path])
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner)
        #expect(!filter.ran(), "the repository's filter ran while the worktree was made")
        #expect(try String(contentsOf: made.worktreeURL.appendingPathComponent("README.md"), encoding: .utf8) == "initial")
        try lab.git(["worktree", "add", "-q", "-b", "control", lab.folder.appendingPathComponent("control").path])
        #expect(filter.ran(), "control: git without the guards runs the filter")
    }

    @Test func aLongRunningFilterTheRepositoryDefinesDoesNotRun() async throws {
        let lab = try Lab()
        try lab.makeRepository()
        let filter = try lab.program("process", passingInput: true)
        try lab.git(["config", "--local", "filter.evil.process", filter.path])
        _ = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner)
        #expect(!filter.ran(), "the filter.evil.process program of the repository ran")
    }

    @Test func aFilterThatAFileTheConfigurationIncludesDefinesDoesNotRun() async throws {
        let lab = try Lab()
        try lab.makeRepository()
        let filter = try lab.program("included", passingInput: true)
        // A repository that arrives as a folder brings its own `.git`, and its configuration can include a file beside it.
        try "[filter \"evil\"]\n\tsmudge = \(filter.path)\n".write(to: lab.repository.appendingPathComponent(".git/extra.cfg"), atomically: true, encoding: .utf8)
        try lab.git(["config", "--local", "include.path", "extra.cfg"])
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner)
        #expect(made.wasCreated)
        #expect(!filter.ran(), "the filter that an included file defines ran while the worktree was made")
    }

    /// What a conditional include brings in is decided by the branch and the git directory of the folder git reads it in: `onbranch:` matches in the new worktree, whose branch it is, and
    /// not in the repository that `worktree add` runs in, so a filter defined there was never found. The worktree is refused instead.
    @Test func aConditionalIncludeOfTheRepositoryIsRefusedAndNothingItDefinesRuns() async throws {
        let lab = try Lab()
        try lab.makeRepository()
        let filter = try lab.program("conditional", passingInput: true)
        try "[filter \"evil\"]\n\tsmudge = \(filter.path)\n".write(to: lab.repository.appendingPathComponent(".git/branch.cfg"), atomically: true, encoding: .utf8)
        try lab.git(["config", "--local", "includeIf.onbranch:rh/**.path", "branch.cfg"])
        await #expect(throws: WorktreeError.self) { _ = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "rh/isolated", runner: lab.runner) }
        #expect(!filter.ran(), "the filter that a conditional include defines ran while the worktree was made")
        let attempt = lab.folder.appendingPathComponent("attempt")
        _ = try? lab.git(["worktree", "add", "-q", "-b", "rh/control", attempt.path])
        #expect(filter.ran(), "control: git without the guards runs the filter in the worktree it makes")
    }

    @Test func aFilterTheWorktreeConfigurationDefinesDoesNotRun() async throws {
        let lab = try Lab()
        try lab.makeRepository()
        let filter = try lab.program("worktreeconfig", passingInput: true)
        try lab.git(["config", "--local", "extensions.worktreeConfig", "true"])
        try "[filter \"evil\"]\n\tsmudge = \(filter.path)\n".write(to: lab.repository.appendingPathComponent(".git/config.worktree"), atomically: true, encoding: .utf8)
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner)
        #expect(made.wasCreated)
        #expect(!filter.ran(), "the filter that config.worktree defines ran while the worktree was made")
    }

    /// `-c filter.<driver>.smudge=` is split by git at the first `=`: a driver whose name has one was never blanked, though it is in `.git/config` itself.
    /// Measured: a filter that is `required` and has no command makes git fail ("smudge filter evil failed"), so the filters are blanked and no longer required.
    @Test func aRequiredFilterOfTheRepositoryDoesNotStopTheWorktreeFromBeingMade() async throws {
        let lab = try Lab()
        try lab.makeRepository()
        let filter = try lab.program("required", passingInput: true)
        try lab.git(["config", "--local", "filter.evil.smudge", filter.path])
        try lab.git(["config", "--local", "filter.evil.clean", filter.path])
        try lab.git(["config", "--local", "filter.evil.required", "true"])
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner)
        #expect(made.wasCreated)
        #expect(!filter.ran())
        #expect(await GitWorktreeManager.discardIfUnchanged(made, gitRoot: lab.repository, runner: lab.runner), "the status after it failed for the required filter")
    }

    @Test func aFilterWhoseNameHasAnEqualsSignDoesNotRun() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: "* filter=a=b\n")
        let filter = try lab.program("equals", passingInput: true)
        try lab.git(["config", "--local", "filter.a=b.smudge", filter.path])
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner)
        #expect(made.wasCreated)
        #expect(!filter.ran(), "the filter whose name has an equals sign ran while the worktree was made")
        try lab.git(["worktree", "add", "-q", "-b", "control", lab.folder.appendingPathComponent("control").path])
        #expect(filter.ran(), "control: git without the guards runs the filter")
    }

    @Test func aFilterWhoseNameStartsWithACombiningMarkDoesNotRun() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: "* filter=\u{301}x\n")
        let filter = try lab.program("mark", passingInput: true)
        try lab.git(["config", "--local", "filter.\u{301}x.smudge", filter.path])
        _ = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner)
        #expect(!filter.ran(), "the filter whose name starts with a combining mark ran")
    }

    @Test func thePersonsOwnFiltersStillRun() async throws {
        let lab = try Lab()
        try lab.makeRepository()
        let filter = try lab.program("mine", passingInput: true)
        // Git LFS lives in the global configuration: the person chose it, and a worktree without it would hold pointer files.
        try lab.git(["config", "--global", "filter.evil.smudge", filter.path])
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner)
        #expect(made.wasCreated)
        #expect(filter.ran(), "a filter of the person's own configuration was switched off")
    }

    @Test func removingAWorktreeDoesNotRunTheRepositorysFsmonitorProgramOrHooks() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "scratch", runner: lab.runner)
        let monitor = try lab.program("monitor")
        try lab.git(["config", "--local", "core.fsmonitor", monitor.path])
        let hook = try lab.program("hook")
        try FileManager.default.copyItem(atPath: hook.path, toPath: lab.repository.appendingPathComponent(".git/hooks/post-index-change").path)
        let second = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "control", runner: lab.runner)
        #expect(!monitor.ran() && !hook.ran(), "set up: making a worktree ran nothing")

        _ = try await GitWorktreeManager.removeWorktree(worktreePath: "scratch", gitRoot: lab.repository, runner: lab.runner)
        #expect(!FileManager.default.fileExists(atPath: made.worktreeURL.path))
        #expect(!monitor.ran(), "`git worktree remove` ran the repository's core.fsmonitor program")
        #expect(!hook.ran(), "`git worktree remove` ran a hook of the repository")
        try lab.git(["worktree", "remove", second.worktreeURL.path])
        #expect(monitor.ran(), "control: git without the guards runs the monitor when it removes a worktree")
    }

    @Test func removingAWorktreeDoesNotRunACleanFilterTheWorktreeConfigurationDefines() async throws {
        let lab = try Lab()
        try lab.makeRepository()
        let filter = try lab.program("clean", passingInput: true)
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "scratch", runner: lab.runner)
        let control = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "control", runner: lab.runner)
        // Defined for those worktrees only (`git worktree remove` runs its status there, with their configuration): not in the main folder's.
        try lab.git(["config", "--local", "extensions.worktreeConfig", "true"])
        for worktree in [made, control] {
            try lab.makeLookRecentlyWritten(worktree.worktreeURL)
            let path = try lab.git(["rev-parse", "--git-path", "config.worktree"], in: worktree.worktreeURL).trimmingCharacters(in: .whitespacesAndNewlines)
            try "[filter \"evil\"]\n\tclean = \(filter.path)\n".write(to: URL(fileURLWithPath: path, relativeTo: worktree.worktreeURL), atomically: true, encoding: .utf8)
        }

        _ = try await GitWorktreeManager.removeWorktree(worktreePath: "scratch", gitRoot: lab.repository, runner: lab.runner)
        #expect(!FileManager.default.fileExists(atPath: made.worktreeURL.path))
        #expect(!filter.ran(), "the status that `git worktree remove` runs applied a clean filter of the worktree's own configuration")
        try lab.git(["worktree", "remove", control.worktreeURL.path])
        #expect(filter.ran(), "control: git without the guards runs the filter when it removes a worktree")
    }

    /// The filter is defined directly in `.git/config`, the one case the first guard handled for `worktree add`; the `git status` that `discardIfUnchanged` runs
    /// in the new worktree compares the files it just wrote with the index, which runs the filter's `clean` command.
    @Test func discardingAnUnusedWorktreeDoesNotRunTheRepositorysCleanFilter() async throws {
        let lab = try Lab()
        try lab.makeRepository()
        let filter = try lab.program("clean", passingInput: true)
        try lab.git(["config", "--local", "filter.evil.clean", filter.path])
        try lab.git(["config", "--local", "filter.evil.smudge", "cat"])
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "unused", runner: lab.runner)
        let control = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "control", runner: lab.runner)
        #expect(!filter.ran(), "set up: creating the worktrees ran nothing")
        try lab.makeLookRecentlyWritten(made.worktreeURL)
        try lab.makeLookRecentlyWritten(control.worktreeURL)

        #expect(await GitWorktreeManager.discardIfUnchanged(made, gitRoot: lab.repository, runner: lab.runner))
        #expect(!filter.ran(), "the `git status` of `discardIfUnchanged` ran the repository's clean filter")
        try lab.git(["status", "--porcelain", "--untracked-files=all"], in: control.worktreeURL)
        #expect(filter.ran(), "control: the same status without the guards runs the filter")
    }

    @Test func discardingAnUnusedWorktreeDoesNotRunTheRepositorysFsmonitorProgram() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        let monitor = try lab.program("monitor")
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "unused", runner: lab.runner)
        let control = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "control", runner: lab.runner)
        try lab.git(["config", "--local", "core.fsmonitor", monitor.path])

        #expect(await GitWorktreeManager.discardIfUnchanged(made, gitRoot: lab.repository, runner: lab.runner))
        #expect(!monitor.ran(), "the `git status` of `discardIfUnchanged` ran the repository's core.fsmonitor program")
        try lab.git(["status", "--porcelain", "--untracked-files=all"], in: control.worktreeURL)
        #expect(monitor.ran(), "control: the same status without the guards runs the monitor")
    }

    @Test func deletingTheBranchDoesNotRunTheReferenceTransactionHook() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        _ = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "done", runner: lab.runner)
        let hook = try lab.program("hook")
        try FileManager.default.copyItem(atPath: hook.path, toPath: lab.repository.appendingPathComponent(".git/hooks/reference-transaction").path)
        let removal = try await GitWorktreeManager.removeWorktree(worktreePath: "done", gitRoot: lab.repository, deleteBranch: true, runner: lab.runner)
        #expect(removal.branchDeleted)
        #expect(!hook.ran(), "`git branch -d` ran the repository's reference-transaction hook")
        try lab.git(["branch", "control"])
        #expect(hook.ran(), "control: git without the guards runs the hook when a branch changes")
    }

    /// A clone that lacks its files fetches them from its promisor remote while a worktree is checked out, and that starts whatever the remote's URL names
    /// (`ext::<program>`, which `protocol.ext.allow` lets the repository allow for itself), the `core.sshCommand` of the repository, or its credential helper.
    @Test func aPartialCloneDoesNotFetchFromItsPromisorRemoteWhileAWorktreeIsMade() async throws {
        let lab = try Lab()
        let origin = lab.folder.appendingPathComponent("origin")
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try lab.git(["init", "-q"], in: origin)
        try "initial".write(to: origin.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try lab.git(["add", "README.md"], in: origin)
        try lab.git(["commit", "-q", "-m", "initial"], in: origin)
        try lab.git(["config", "uploadpack.allowFilter", "true"], in: origin)
        try lab.git(["config", "uploadpack.allowAnySHA1InWant", "true"], in: origin)
        try lab.git(["clone", "-q", "--no-checkout", "--filter=blob:none", "file://\(origin.path)", lab.repository.path], in: lab.folder)

        let transport = try lab.program("transport")
        try lab.git(["config", "protocol.ext.allow", "always"])
        try lab.git(["config", "remote.origin.url", "ext::\(transport.path) %S"])
        try lab.git(["config", "core.sshCommand", transport.path])
        let attempt = lab.folder.appendingPathComponent("attempt")
        await #expect(throws: (any Error).self) { _ = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: lab.runner) }
        #expect(!transport.ran(), "a partial clone fetched from its promisor remote and started the program its URL names")

        _ = try? lab.git(["worktree", "add", "-q", "-b", "control", attempt.path])
        #expect(transport.ran(), "control: git without the guards starts the program")
    }

    /// Measured: with a named pipe in `include.path`, every git command in the repository waits for a writer. The commands that only read are stopped.
    @Test func aRepositoryWhoseConfigurationIncludesANamedPipeDoesNotHoldACallForEver() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        let pipe = lab.repository.appendingPathComponent(".git/pipe.cfg")
        #expect(mkfifo(pipe.path, 0o600) == 0)
        try lab.git(["config", "--local", "include.path", "pipe.cfg"])
        let runner = ImpatientRunner(base: lab.runner)
        await #expect(throws: ExecutionError.self) { _ = try await GitWorktreeManager.listWorktrees(in: lab.repository, runner: runner) }
        await #expect(throws: ExecutionError.self) { _ = try await GitWorktreeManager.prepareWorktree(gitRoot: lab.repository, branch: "isolated", runner: runner) }
    }

    @Test func aFolderNameWithALineBreakDoesNotChangeWhatTheListSays() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        let odd = lab.folder.appendingPathComponent("odd\nworktree /tmp/forged\nbranch refs/heads/rh/forged")
        try lab.git(["worktree", "add", "-q", "-b", "odd", odd.path])
        let entries = try await GitWorktreeManager.listWorktrees(in: lab.repository, runner: lab.runner)
        #expect(entries.count == 2)
        #expect(entries.last?.path == odd.standardizedFileURL.path, "the path of the worktree was replaced: \(entries.last?.path ?? "")")
        #expect(entries.last?.branch == "odd")
        #expect(!entries.contains { $0.path == "/tmp/forged" })
    }
}

/// A repository is somebody else's code, and a git command that was not built by `GitCommand.step` has none of the guards. Whoever adds one has to name git's
/// program, so naming it anywhere else than `GitCommand` fails here, and the `step` function is the one door.
@Suite("git guard: the one place that starts git")
struct GitIsStartedInOnePlaceTests {
    @Test func noFileOfTheProductButGitCommandNamesGitsProgram() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var offenders: [String] = []
        var seen = 0
        for folder in ["Sources", "Apps"] {
            let files = try #require(FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil))
            for case let file as URL in files where file.pathExtension == "swift" && file.lastPathComponent != "GitCommand.swift" {
                seen += 1
                let text = try String(contentsOf: file, encoding: .utf8)
                for needle in ["bin/git", "GitCommand.executable", "\"git\""] where text.contains(needle) { offenders.append("\(file.lastPathComponent) names \(needle)") }
            }
        }
        #expect(seen > 100, "the scan did not find the sources")
        #expect(offenders.isEmpty, "git is started outside GitCommand.step: \(offenders)")
    }
}

/// What each item is in the commit is asked on git's input, so the names are not handed over decomposed as arguments are.
private func batchCheck(in directory: String, input: String) -> ProcessStep {
    var step = git(["-C", directory, "cat-file", "--batch-check=%(objecttype)", "-Z"])
    step.standardInput = input
    return step
}

@Suite("git guard: reading a repository for its link")
struct RepositoryReaderTests {
    private let commit = "d89f86032883bae7ef136d543343639777e2455a"

    @Test func readingTheRemoteAndTheCommitCarriesTheGuardsAndPrefersTheUpstream() async throws {
        let runner = FakeProcessRunner(results: [
            ProcessResult(status: 0, standardOutput: "/work/app\n"),
            ProcessResult(status: 0, standardOutput: commit + "\n"),
            ProcessResult(status: 0, standardOutput: "refs/heads/main\n"),
            ProcessResult(status: 0, standardOutput: "upstream\n"), ProcessResult(status: 1), ProcessResult(status: 1),
            ProcessResult(status: 0, standardOutput: "origin\nupstream\n"),
            ProcessResult(status: 0, standardOutput: ""),
            ProcessResult(status: 0, standardOutput: "https://github.com/o/r.git\n"),
            ProcessResult(status: 0, standardOutput: "blob\u{0}")
        ])
        let item = URL(fileURLWithPath: "/work/app/src/a.swift")
        let facts = FakeSystemFacts(directories: ["/work/app", "/work/app/src"], files: ["/work/app/src/a.swift"], gitRoots: ["/work/app"])
        let states = try await RepositoryReader.read(items: [item], facts: facts, runner: runner)
        #expect(runner.recorded == [
            git(["-C", "/work/app/src", "rev-parse", "--show-toplevel"]),
            git(["-C", "/work/app", "rev-parse", "--verify", "--quiet", "HEAD^{commit}"]),
            git(["-C", "/work/app", "symbolic-ref", "-q", "HEAD"]),
            git(["-C", "/work/app", "config", "--get", "branch.main.remote"]),
            git(["-C", "/work/app", "config", "--get", "branch.main.pushRemote"]),
            git(["-C", "/work/app", "config", "--get", "remote.pushDefault"]),
            git(["-C", "/work/app", "remote"]),
            git(["-C", "/work/app", "rev-list", "-n1", commit, "--not", "--remotes=upstream"]),
            git(["-C", "/work/app", "remote", "get-url", "upstream"]),
            batchCheck(in: "/work/app", input: "\(commit):src/a.swift\u{0}")
        ])
        #expect(states[item] == RepositoryState(root: URL(fileURLWithPath: "/work/app"), itemPath: ["src", "a.swift"], remoteName: "upstream",
                                                remoteNames: ["origin", "upstream"], remoteURL: "https://github.com/o/r.git", commit: commit, isPushed: true, kind: .file))
    }

    /// Which remote: the upstream, then the push remote (a fork that has the commit when the upstream does not), then origin, then the only
    /// one; a name with a slash is a remote too, and one that starts with "-" or would be a pattern is never used.
    @Test func theFirstRemoteThatHasTheCommitIsChosen() async throws {
        func chosen(upstream: String? = nil, pushRemote: String? = nil, remotes: String, having: Set<String>) async throws -> String? {
            var results = [ProcessResult(status: 0, standardOutput: "/work/app\n"), ProcessResult(status: 0, standardOutput: commit + "\n"),
                           ProcessResult(status: 0, standardOutput: "refs/heads/feature\n"),
                           upstream.map { ProcessResult(status: 0, standardOutput: $0 + "\n") } ?? ProcessResult(status: 1),
                           pushRemote.map { ProcessResult(status: 0, standardOutput: $0 + "\n") } ?? ProcessResult(status: 1),
                           ProcessResult(status: 1), ProcessResult(status: 0, standardOutput: remotes)]
            let names = remotes.split(separator: "\n").map(String.init)
            var order: [String] = []
            for name in [upstream, pushRemote, names.contains("origin") ? "origin" : nil, names.count == 1 ? names.first : nil].compactMap({ $0 })
            where names.contains(name) && !order.contains(name) && !name.hasPrefix("-") && !name.contains("*") { order.append(name) }
            for name in order {
                results.append(ProcessResult(status: 0, standardOutput: having.contains(name) ? "" : commit + "\n"))
                if having.contains(name) { break }
            }
            if !order.isEmpty { results.append(ProcessResult(status: 0, standardOutput: "https://github.com/o/r\n")) }
            results.append(ProcessResult(status: 0, standardOutput: "tree\u{0}"))
            let root = URL(fileURLWithPath: "/work/app")
            let facts = FakeSystemFacts(directories: ["/work/app"], gitRoots: ["/work/app"])
            return try await RepositoryReader.read(items: [root], facts: facts, runner: FakeProcessRunner(results: results))[root]?.remoteName
        }
        #expect(try await chosen(upstream: "origin", pushRemote: "me/fork", remotes: "origin\nme/fork\n", having: ["me/fork"]) == "me/fork")
        #expect(try await chosen(upstream: "origin", pushRemote: "me/fork", remotes: "origin\nme/fork\n", having: []) == "origin")
        #expect(try await chosen(remotes: "fork\norigin\n", having: ["origin"]) == "origin")
        #expect(try await chosen(remotes: "me/fork\n", having: ["me/fork"]) == "me/fork")
        #expect(try await chosen(remotes: "fork\nmine\n", having: []) == nil)
        #expect(try await chosen(remotes: "o*\n", having: []) == nil)
        #expect(try await chosen(remotes: "-x\n", having: []) == nil)
    }

    @Test func theRealGitReadsTheRepositoryAndStartsNoneOfItsPrograms() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        let precomposed = "\u{E9}t\u{E9}.md"
        try "x".write(to: lab.repository.appendingPathComponent("-x"), atomically: true, encoding: .utf8)
        try "x".write(to: lab.repository.appendingPathComponent(precomposed), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: lab.repository.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "x".write(to: lab.repository.appendingPathComponent("sub/x.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: lab.repository.appendingPathComponent("alias").path, withDestinationPath: "sub")
        try lab.git(["add", "--", "-x", precomposed, "sub/x.txt", "alias"])
        try lab.git(["commit", "-q", "-m", "names"])
        // A tag called like the branch: `rev-parse --abbrev-ref HEAD` says heads/main, and the upstream would be missed.
        try lab.git(["tag", "main"])
        try lab.git(["remote", "add", "origin", "https://github.com/someone/other"])
        try lab.git(["remote", "add", "upstream", "gh:owner/repo"])
        try lab.git(["config", "--local", "url.https://github.com/.insteadOf", "gh:"])
        try lab.git(["update-ref", "refs/remotes/upstream/main", "HEAD"])
        try lab.git(["update-ref", "refs/remotes/origin/main", "HEAD"])
        try lab.git(["config", "--local", "branch.main.remote", "upstream"])
        // An empty .git folder is no repository to git: the item is still in the outer one.
        try FileManager.default.createDirectory(at: lab.repository.appendingPathComponent("sub/.git"), withIntermediateDirectories: true)
        try "new".write(to: lab.repository.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        // Everything the repository can name that git would start.
        let program = try lab.program("started", passingInput: true)
        for hook in ["post-checkout", "reference-transaction", "post-index-change", "pre-commit"] {
            try FileManager.default.copyItem(atPath: program.path, toPath: lab.repository.appendingPathComponent(".git/hooks/\(hook)").path)
        }
        try lab.git(["config", "--local", "core.fsmonitor", program.path])
        for key in ["smudge", "clean", "process"] { try lab.git(["config", "--local", "filter.evil.\(key)", program.path]) }
        try "* filter=evil\n".write(to: lab.repository.appendingPathComponent(".gitattributes"), atomically: true, encoding: .utf8)
        try lab.git(["config", "--local", "core.pager", program.path])
        try lab.git(["config", "--local", "core.sshCommand", program.path])

        let root = lab.repository
        let facts = FakeSystemFacts(directories: [root.path, root.appendingPathComponent("sub").path, root.appendingPathComponent("alias").path],
                                    gitRoots: [root.path, root.appendingPathComponent("sub").path])
        let decomposed = root.appendingPathComponent(precomposed.decomposedStringWithCanonicalMapping)
        let inSub = root.appendingPathComponent("sub/x.txt")
        let alias = root.appendingPathComponent("alias")
        let items = [root.appendingPathComponent("README.md"), root.appendingPathComponent("-x"), decomposed, root.appendingPathComponent("new.txt"), root, inSub, alias]
        let states = try await RepositoryReader.read(items: items, facts: facts, runner: lab.runner)
        #expect(!program.ran(), "a program of the repository ran while it was read")
        let readme = try #require(states[items[0]])
        #expect(readme.remoteName == "upstream", "the upstream was missed beside a tag of the branch's name: \(readme)")
        #expect(readme.remoteURL == "https://github.com/owner/repo", "insteadOf was not applied: \(readme)")
        #expect(readme.commit?.count == 40 && readme.isPushed && readme.kind == .file)
        #expect(states[items[1]]?.kind == .file, "a name that starts with - was read as an option")
        #expect(states[items[2]]?.kind == .file, "the decomposed name of a precomposed file was not found")
        #expect(states[items[3]].map { $0.kind == nil && $0.gitError == nil } == true, "an untracked file was said to be in the commit")
        #expect(states[items[4]]?.kind == .folder && states[items[4]]?.itemPath == [])
        #expect(states[inSub]?.itemPath == ["sub", "x.txt"] && states[inSub]?.kind == .file, "an empty .git folder made sub a repository: \(String(describing: states[inSub]))")
        #expect(states[alias]?.kind == .file, "a committed link to a folder is a file in the commit")

        // A commit that only this clone has is not pushed.
        let tree = try lab.git(["rev-parse", "HEAD^{tree}"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let local = try lab.git(["commit-tree", tree, "-p", "HEAD", "-m", "local"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try lab.git(["update-ref", "refs/heads/main", local])
        // That unguarded update-ref ran the repository's reference-transaction hook: the control that shows the program can be seen to run.
        #expect(program.ran(), "control: git without the guards runs the repository's hook")
        try FileManager.default.removeItem(at: lab.outside.appendingPathComponent("started.ran"))
        let after = try await RepositoryReader.read(items: [root], facts: facts, runner: lab.runner)
        #expect(after[root]?.commit == local && after[root]?.isPushed == false)
        #expect(!program.ran())
    }

    /// `rh` started from a hook or by another git command can inherit GIT_DIR, which makes git read that repository whatever `-C` says.
    @Test func anInheritedGitDirDoesNotChangeTheRepository() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        try lab.git(["remote", "add", "origin", "https://github.com/owner/repo"])
        try lab.git(["update-ref", "refs/remotes/origin/main", "HEAD"])
        let other = lab.folder.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try lab.git(["init", "-q"], in: other)
        try lab.git(["remote", "add", "origin", "https://codeberg.org/someone/other"], in: other)
        let runner = EnvironmentRunner(base: LiveProcessRunner(), adding: lab.environment.merging(["GIT_DIR": other.appendingPathComponent(".git").path]) { $1 })
        let item = lab.repository.appendingPathComponent("README.md")
        let states = try await RepositoryReader.read(items: [item], facts: FakeSystemFacts(gitRoots: [lab.repository.path]), runner: runner)
        #expect(states[item]?.remoteURL == "https://github.com/owner/repo", "the inherited GIT_DIR chose another repository: \(String(describing: states[item]))")
    }

    /// A replace ref swaps a commit for another when git reads it: the link would name a file that the host's commit does not have.
    @Test func aReplaceRefDoesNotChangeWhatIsInTheCommit() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        try lab.git(["remote", "add", "origin", "https://github.com/owner/repo"])
        try lab.git(["update-ref", "refs/remotes/origin/main", "HEAD"])
        let pushed = try lab.git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try "b".write(to: lab.repository.appendingPathComponent("only-in-b"), atomically: true, encoding: .utf8)
        try lab.git(["add", "only-in-b"])
        try lab.git(["commit", "-q", "-m", "b"])
        let other = try lab.git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try lab.git(["reset", "-q", "--soft", pushed])
        try lab.git(["replace", pushed, other])
        let item = lab.repository.appendingPathComponent("only-in-b")
        let states = try await RepositoryReader.read(items: [item], facts: FakeSystemFacts(gitRoots: [lab.repository.path]), runner: lab.runner)
        #expect(states[item]?.commit == pushed)
        #expect(states[item]?.kind == nil, "the replace ref put a file into the pushed commit")
    }

    /// A `.git` file that names a folder that is not there: git's own reason is what the person is told, not "no remote".
    @Test func gitsOwnErrorIsKept() async throws {
        let lab = try Lab()
        try "gitdir: /nonexistent\n".write(to: lab.repository.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let item = lab.repository
        let states = try await RepositoryReader.read(items: [item], facts: FakeSystemFacts(directories: [item.path], gitRoots: [item.path]), runner: lab.runner)
        #expect(states[item]?.gitError?.contains("not a git repository") == true, "\(String(describing: states[item]))")
    }

    /// A submodule is a commit of another repository in this one's tree: told apart from a folder, since its pages are in that repository.
    @Test func aSubmoduleIsToldApartFromAFolder() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        let head = try lab.git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try lab.git(["update-index", "--add", "--cacheinfo", "160000,\(head),mod"])
        try lab.git(["commit", "-q", "-m", "submodule"])
        let mod = lab.repository.appendingPathComponent("mod")
        try FileManager.default.createDirectory(at: mod, withIntermediateDirectories: true)
        let facts = FakeSystemFacts(directories: [lab.repository.path, mod.path], gitRoots: [lab.repository.path])
        let states = try await RepositoryReader.read(items: [mod], facts: facts, runner: lab.runner)
        #expect(states[mod]?.kind == .submodule, "\(String(describing: states[mod]))")
    }

    /// git that does not precompose names (`core.precomposeunicode=false`) finds a precomposed file only by its precomposed name.
    @Test func theNameIsLookedUpPrecomposed() async throws {
        let lab = try Lab()
        try lab.makeRepository(attributes: nil)
        let precomposed = "caf\u{E9}.txt"
        try "x".write(to: lab.repository.appendingPathComponent(precomposed), atomically: true, encoding: .utf8)
        try lab.git(["add", precomposed])
        try lab.git(["commit", "-q", "-m", "cafe"])
        try lab.git(["config", "--local", "core.precomposeunicode", "false"])
        let item = lab.repository.appendingPathComponent(precomposed.decomposedStringWithCanonicalMapping)
        let states = try await RepositoryReader.read(items: [item], facts: FakeSystemFacts(gitRoots: [lab.repository.path]), runner: lab.runner)
        #expect(states[item]?.kind == .file, "\(String(describing: states[item]))")
    }
}
