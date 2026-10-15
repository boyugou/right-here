import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

private struct Home {
    let home: URL
    let paths: RHPaths

    init() throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
    }

    func cleanUp() {
        // A test may have made the folder unwritable.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.configDirectory.path)
        try? FileManager.default.removeItem(at: home)
    }

    func writeConfig() throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try "[general]\n".write(to: paths.configFile, atomically: true, encoding: .utf8)
    }

    /// The facts of this home: the config file is known to exist when it was written. A trial home, so nothing is registered for the
    /// whole Mac whatever the test does.
    func actions(_ runner: any ProcessRunner) -> SetupActions {
        let existing = FileManager.default.fileExists(atPath: paths.configFile.path) ? [paths.configFile.path] : []
        return SetupActions(facts: FakeSystemFacts(homeDirectory: home, files: Set(existing)), paths: paths, runner: runner, helperPath: "/opt/app/rh", trialHome: home)
    }
}

/// A runner whose process cannot even be started.
private struct BrokenRunner: ProcessRunner {
    struct Failure: LocalizedError {
        var errorDescription: String? { "The file could not be opened." }
    }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult { throw Failure() }
}

@Suite("SetupNotice")
struct SetupNoticeTests {
    @Test func everyNoticeIsACatalogMessageInEnglish() {
        #expect(SetupNotice.promptCopied.message.english() == "Setup prompt copied. Paste it into your AI assistant.")
        #expect(SetupNotice.mcpConfigurationCopied.message.english() == "MCP configuration copied. Paste it into your assistant's MCP settings.")
        #expect(SetupNotice.pluginCommandsCopied.message.english() == "Plugin commands copied. Paste them into Claude Code.")
        #expect(SetupNotice.worktreeRemoved("~/work/.right-here/worktrees/x").message.english() == "Removed the worktree ~/work/.right-here/worktrees/x.")
        #expect(SetupNotice.notARepository("~/notes").message.english() == "~/notes is not in a git repository.")
        #expect(SetupNotice.stopped(status: 3).message.english() == "It did not finish (exit status 3).")
        #expect(SetupNotice.notRemovable.message.english() == "Right Here did not remove this worktree: it is not one Right Here made, so it is left alone.")
    }

    @Test func aFailureIsShownAsItsOwnWordsInEveryLanguage() {
        let notice = SetupNotice.failed("error: something git said")
        for language in Localizer.supportedLanguages {
            #expect(Localizer(languages: [language]).render(notice.message) == "error: something git said", "\(language)")
        }
    }

    @Test func onlyWhatDidNotWorkIsAProblem() {
        let problems: [SetupNotice] = [.failed("x"), .stopped(status: 1), .notARepository("/x"), .notRemovable]
        let confirmations: [SetupNotice] = [.promptCopied, .mcpConfigurationCopied, .pluginCommandsCopied, .worktreeRemoved("/x")]
        #expect(problems.allSatisfy { $0.isProblem })
        #expect(confirmations.allSatisfy { !$0.isProblem })
    }
}

@Suite("SetupActions")
struct SetupActionsTests {
    @Test func settingUpRunsTheSameSetupAsTheCommandLineAndSaysNothingWhenItWorked() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let result = await machine.actions(FakeProcessRunner()).setUp()
        #expect(result.notice == nil)
        let report = try #require(result.report)
        #expect(report.ok && report.step(.config)?.outcome == .created)
        #expect(FileManager.default.fileExists(atPath: machine.paths.configFile.path))
        #expect(Installer(home: machine.home).installedRunnerTarget() == "/opt/app/rh", "the runner script points at the rh inside the app")
    }

    @Test func whatThePersonChoseIsWhatTheConfigSays() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let result = await machine.actions(FakeProcessRunner()).setUp(SetupChoices(terminal: "terminal", editor: "zed", agents: ["claude"]))
        #expect(result.notice == nil)
        let config = ConfigStore.load(paths: machine.paths).config
        #expect(config.terminal == "terminal" && config.editor == "zed" && config.enabledAgents == ["claude"])
    }

    @Test func aSecondSetUpLeavesTheConfigAndSaysItChangedNothing() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        _ = await machine.actions(FakeProcessRunner()).setUp(SetupChoices(terminal: "terminal", editor: "zed", agents: []))
        let before = try String(contentsOf: machine.paths.configFile, encoding: .utf8)
        let again = await machine.actions(FakeProcessRunner()).setUp(SetupChoices(terminal: "ghostty", editor: "vscode", agents: ["claude"]))
        #expect(try String(contentsOf: machine.paths.configFile, encoding: .utf8) == before, "the window never rewrites a config that is there")
        #expect(again.report?.steps.allSatisfy { $0.outcome == .unchanged || $0.outcome == .skipped } == true)
    }

    @Test func aStepThatFailedSaysWhyInItsOwnWords() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let installer = Installer(home: machine.home)
        try FileManager.default.createDirectory(at: installer.locations.localBin, withIntermediateDirectories: true)
        try "mine".write(to: installer.cliLink, atomically: true, encoding: .utf8)
        let result = await machine.actions(FakeProcessRunner()).setUp()
        guard case .failed(let text)? = result.notice else { Issue.record("no failure was reported: \(String(describing: result.notice))"); return }
        #expect(text.contains("left alone"), "\(text)")
        #expect(result.report?.step(.config)?.outcome == .created, "the other steps still ran")
    }

    @Test func anAppRunFromTheTemporaryLocationOfADownloadSaysSoAndWritesNothing() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let translocated = "/private/var/folders/ab/cd/T/AppTranslocation/6F1B/d/Right Here.app/Contents/Helpers/rh"
        let actions = SetupActions(facts: FakeSystemFacts(homeDirectory: machine.home), paths: machine.paths, runner: FakeProcessRunner(), helperPath: translocated, trialHome: machine.home)
        let result = await actions.setUp()
        #expect(result.report == nil)
        guard case .failed(let text)? = result.notice else { Issue.record("no failure was reported"); return }
        #expect(text.contains("Move Right Here.app into your Applications folder"))
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configFile.path))
    }

    @Test func aProcessThatCannotBeStartedSaysItInTheSystemsWords() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try machine.writeConfig()
        #expect(await machine.actions(BrokenRunner()).openConfig() == .failed("The file could not be opened."))
    }

    @Test func theConfigIsOpenedInTheDefaultTextEditor() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try machine.writeConfig()
        let runner = FakeProcessRunner()
        #expect(await machine.actions(runner).openConfig() == nil)
        #expect(runner.recorded == [ProcessStep(executable: "/usr/bin/open", arguments: ["-t", machine.paths.configFile.path])])
    }

    @Test func aMissingConfigIsMadeBeforeItIsOpened() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let runner = FakeProcessRunner()
        #expect(await machine.actions(runner).openConfig() == nil)
        #expect(FileManager.default.fileExists(atPath: machine.paths.configFile.path))
        #expect(runner.recorded.last == ProcessStep(executable: "/usr/bin/open", arguments: ["-t", machine.paths.configFile.path]))
    }

    @Test func aConfigThatCouldNotBeMadeIsNotOpened() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        // A file where the config folder goes: it cannot be made.
        try FileManager.default.createDirectory(at: machine.paths.configDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "in the way".write(to: machine.paths.configDirectory, atomically: true, encoding: .utf8)
        let runner = FakeProcessRunner()
        guard case .failed? = await machine.actions(runner).openConfig() else { Issue.record("no failure was reported"); return }
        #expect(!runner.recorded.contains { $0.executable == "/usr/bin/open" })
    }

    @Test func anEditorThatCouldNotBeOpenedIsReported() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try machine.writeConfig()
        let runner = FakeProcessRunner(results: [ProcessResult(status: 1, standardError: "The file does not exist.")])
        #expect(await machine.actions(runner).openConfig() == .failed("The file does not exist."))
    }

    @Test func aRepositoryIsLookedUpInTheFacts() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let facts = FakeSystemFacts(homeDirectory: machine.home, gitRoots: ["/work/app"])
        let actions = SetupActions(facts: facts, paths: machine.paths, runner: FakeProcessRunner(), helperPath: "/opt/app/rh")
        #expect(await actions.repository(containing: URL(fileURLWithPath: "/work/app/Sources")) == URL(fileURLWithPath: "/work/app"))
        #expect(await actions.repository(containing: URL(fileURLWithPath: "/work/notes")) == nil)
    }
}

@Suite("SetupActions: the folders Right Here remembers")
struct SetupFolderEditTests {
    private func seed(_ machine: Home) throws {
        try StateStore(pins: ["/work/app", "/work/web"], recents: ["/work/notes", "/work/app"]).save(paths: machine.paths)
    }

    @Test func aPinGoesAndTheOthersStay() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try seed(machine)
        #expect(await machine.actions(FakeProcessRunner()).unpin("/work/app") == nil)
        let state = StateStore.load(paths: machine.paths)
        #expect(state.pins == ["/work/web"])
        #expect(state.recents == ["/work/notes", "/work/app"])
    }

    @Test func aFolderThatIsNotPinnedChangesNothingAndWritesNothing() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        #expect(await machine.actions(FakeProcessRunner()).unpin("/work/other") == nil)
        #expect(!FileManager.default.fileExists(atPath: machine.paths.stateFile.path))
    }

    @Test func theRecentFoldersAreClearedAndThePinsStay() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try seed(machine)
        #expect(await machine.actions(FakeProcessRunner()).clearRecents() == nil)
        let state = StateStore.load(paths: machine.paths)
        #expect(state.recents.isEmpty)
        #expect(state.pins == ["/work/app", "/work/web"])
    }

    @Test func theFileStaysPrivateToThePerson() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try seed(machine)
        _ = await machine.actions(FakeProcessRunner()).clearRecents()
        let mode = try FileManager.default.attributesOfItem(atPath: machine.paths.stateFile.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func aStateThatCannotBeSavedSaysSoAndLeavesWhatIsOnDiskAlone() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try seed(machine)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: machine.paths.configDirectory.path)
        let notice = await machine.actions(FakeProcessRunner()).clearRecents()
        #expect(notice?.isProblem == true)
        #expect(StateStore.load(paths: machine.paths).recents == ["/work/notes", "/work/app"], "the window must not claim a clear that did not happen")
    }
}
