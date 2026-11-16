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
    func actions(_ runner: any ProcessRunner, directories: Set<String> = [], files: Set<String> = []) -> SetupActions {
        let existing = FileManager.default.fileExists(atPath: paths.configFile.path) ? [paths.configFile.path] : []
        return SetupActions(facts: FakeSystemFacts(homeDirectory: home, directories: directories, files: Set(existing).union(files)),
                            paths: paths, runner: runner, helperPath: "/opt/app/rh", trialHome: home)
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
        let problems: [SetupNotice] = [.failed("x"), .stopped(status: 1), .notARepository("/x"), .notRemovable, .folderUnavailable("/x")]
        let confirmations: [SetupNotice] = [.promptCopied, .mcpConfigurationCopied, .pluginCommandsCopied, .worktreeRemoved("/x"),
                                            .folderPinned("/x"), .folderUnpinned("/x"), .recentsCleared]
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

    @Test func aConfigThatDoesNotParseIsAFailureTheWindowSaysAndNeverASuccess() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        let text = "[general\nterminal = \"ghostty\"\n"
        try text.write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        // The first-run button (with what the person chose) and Install or Repair (without) read the same report.
        for choices in [SetupChoices(terminal: "terminal", editor: "zed", agents: []), SetupChoices()] {
            let result = await machine.actions(FakeProcessRunner()).setUp(choices)
            let report = try #require(result.report)
            #expect(!report.ok && report.step(.config)?.outcome == .failed && report.step(.services)?.outcome == .skipped)
            guard case .failed(let said)? = result.notice else { Issue.record("no failure was reported: \(String(describing: result.notice))"); return }
            #expect(said.contains("line 1: TOML syntax error") && said.contains(machine.paths.configFile.path), "\(said)")
            #expect(result.notice?.isProblem == true)
            #expect(try String(contentsOf: machine.paths.configFile, encoding: .utf8) == text)
        }
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

    @Test func openingAConfigProblemOpensTheFileThatActuallyHasTheError() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try machine.writeConfig()
        let broken = "[general\nterminal = \"ghostty\"\n"
        try broken.write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        let loaded = ConfigStore.load(paths: machine.paths)
        #expect(loaded.result.diagnostics.first { $0.severity == .error }?.file == "config.local.toml")
        let runner = FakeProcessRunner()
        #expect(await machine.actions(runner).openConfig() == nil)
        #expect(runner.recorded == [ProcessStep(executable: "/usr/bin/open", arguments: ["-t", machine.paths.localConfigFile.path])])
        #expect(try String(contentsOf: machine.paths.configFile, encoding: .utf8) == "[general]\n")
        #expect(try String(contentsOf: machine.paths.localConfigFile, encoding: .utf8) == broken)
    }

    @Test func anErrorInTheMainConfigStillOpensTheMainFileWhenAnOverlayExists() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try machine.writeConfig()
        try "[general\n".write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        try "[general]\n".write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        let runner = FakeProcessRunner()
        #expect(await machine.actions(runner).openConfig() == nil)
        #expect(runner.recorded == [ProcessStep(executable: "/usr/bin/open", arguments: ["-t", machine.paths.configFile.path])])
    }

    @Test(arguments: SetupConfigFile.allCases)
    func anExplicitChoiceOpensThatLayerEvenWhenTheOtherOneHasAnError(_ selected: SetupConfigFile) async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let file = machine.home.appendingPathComponent("team's config.toml")
        let paths = RHPaths(environment: ["RH_CONFIG": file.path], home: machine.home)
        for layer in SetupConfigFile.allCases {
            try (layer == selected ? "[general]\n" : "[general\n").write(to: layer.url(relativeTo: file), atomically: true, encoding: .utf8)
        }
        let runner = FakeProcessRunner()
        let actions = SetupActions(facts: FakeSystemFacts(homeDirectory: machine.home), paths: paths, runner: runner, helperPath: "/opt/app/rh")
        #expect(await actions.openConfig(selected) == nil)
        #expect(runner.recorded == [ProcessStep(executable: "/usr/bin/open", arguments: ["-t", selected.url(relativeTo: file).path])])
    }

    @Test func aSelectedLayerThatDisappearsIsNotReplacedWithTheOtherFile() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try machine.writeConfig()
        try "[general]\n".write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: machine.paths.localConfigFile)
        let runner = FakeProcessRunner()
        #expect(await machine.actions(runner).openConfig(.local)?.isProblem == true)
        #expect(runner.recorded.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: machine.paths.localConfigFile.path))
        #expect(try String(contentsOf: machine.paths.configFile, encoding: .utf8) == "[general]\n")
    }

    @Test func aLocalDanglingLinkIsNotMistakenForTheMissingMainFile() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        let target = machine.home.appendingPathComponent("not-created.toml")
        try FileManager.default.createSymbolicLink(at: machine.paths.localConfigFile, withDestinationURL: target)
        let runner = FakeProcessRunner()
        #expect(await machine.actions(runner).openConfig() == nil)
        #expect(runner.recorded == [ProcessStep(executable: "/usr/bin/open", arguments: ["-t", machine.paths.localConfigFile.path])])
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: machine.paths.localConfigFile.path) == target.path)
    }

    @Test func aMissingConfigIsNotMadeByOpeningItAndTheEditorIsNotStarted() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let runner = FakeProcessRunner()
        // The first run makes the config from what the person chooses; a button that made it from what was found would skip that choice.
        guard case .failed(let said)? = await machine.actions(runner).openConfig() else { Issue.record("no failure was reported"); return }
        #expect(said.contains("press Set Up"), "\(said)")
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configFile.path))
        #expect(runner.recorded.isEmpty)
    }

    @Test func installOrRepairNeverMakesTheConfigAndStartsNothing() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let runner = FakeProcessRunner()
        let result = await machine.actions(runner).repair()
        #expect(result.report == nil)
        guard case .failed(let said)? = result.notice else { Issue.record("no failure was reported"); return }
        #expect(said.contains("press Set Up"), "\(said)")
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configFile.path))
        #expect(!FileManager.default.fileExists(atPath: Installer(home: machine.home).runnerScript.path), "nothing was installed either")
        #expect(runner.recorded.isEmpty)
    }

    @Test func installOrRepairOfAMacThatHasAConfigIsTheSetupWithoutChoices() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try machine.writeConfig()
        let result = await machine.actions(FakeProcessRunner()).repair()
        let report = try #require(result.report)
        #expect(report.step(.config)?.outcome == .unchanged)
        #expect(report.step(.runnerScript)?.outcome == .created)
    }

    @Test func aConfigThatIsALinkToNothingIsARepairNotAFirstRun() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: machine.paths.configFile.path, withDestinationPath: machine.home.appendingPathComponent("dotfiles/config.toml").path)
        // The window offers no first run for it (`SetupLoader`), so its buttons must not answer "choose first": the setup runs, says the config cannot be used, and leaves the link.
        let result = await machine.actions(FakeProcessRunner()).repair()
        #expect(result.report?.step(.config)?.outcome == .failed)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: machine.paths.configFile.path) == machine.home.appendingPathComponent("dotfiles/config.toml").path)
    }

    @Test func installOrRepairWithOnlyThePerMachineOverlayDoesNotMakeTheBaseConfig() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        try "[general]\n".write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        // The window takes the overlay for a config (no first run to offer), so the repair that follows must not make `config.toml` from what it found.
        let result = await machine.actions(FakeProcessRunner()).repair()
        let report = try #require(result.report)
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configFile.path), "the base config was made without the choice the first run asks for")
        #expect(report.step(.config)?.outcome == .skipped)
        #expect(report.step(.runnerScript)?.outcome == .created, "the rest of the repair ran")
    }

    @Test func aMacWithOnlyThePerMachineOverlayHasAConfigTheEditorOpens() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        try "[general]\n".write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        let runner = FakeProcessRunner()
        #expect(await machine.actions(runner).openConfig() == nil)
        #expect(runner.recorded == [ProcessStep(executable: "/usr/bin/open", arguments: ["-t", machine.paths.localConfigFile.path])])
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
    @Test func failedReadsNeverClaimSuccessfulFolderEdits() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try seed(machine)
        let original = Data("pins = [\"/work/app\"".utf8)
        try original.write(to: machine.paths.stateFile)
        let actions = machine.actions(FakeProcessRunner(), directories: ["/work/new"])
        let results = [await actions.pin("/work/new"), await actions.unpin("/work/app"), await actions.clearRecents()]
        for notice in results {
            guard case .savedFoldersProblem(let message) = notice else { Issue.record("The edit did not report its saved-folder error."); continue }
            #expect(notice?.isProblem == true)
            #expect(!message.english().contains(machine.paths.home.path))
        }
        #expect(try Data(contentsOf: machine.paths.stateFile) == original)
    }

    @Test func theRecoveryActionRevealsTheStateFileWithoutOpeningIt() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let runner = FakeProcessRunner()
        #expect(await machine.actions(runner).revealSavedFolders() == nil)
        #expect(runner.recorded == [ProcessStep(executable: "/usr/bin/open", arguments: ["-R", machine.paths.stateFile.path])])
        #expect(!FileManager.default.fileExists(atPath: machine.paths.stateFile.path))
    }

    private func seed(_ machine: Home) throws {
        try StateStore(pins: ["/work/app", "/work/web"], recents: ["/work/notes", "/work/app"]).save(paths: machine.paths)
    }

    @Test func aFolderCanBePinnedFromTheWindowWithoutChangingConfigOrRecents() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try seed(machine)
        let runner = FakeProcessRunner()
        let actions = machine.actions(runner, directories: ["/work/new"])
        #expect(await actions.pin("/work/new") == nil)
        #expect(await actions.pin("/work/./new/") == nil)
        let state = try StateStore.load(paths: machine.paths)
        #expect(state.pins == ["/work/app", "/work/web", "/work/new"])
        #expect(state.recents == ["/work/notes", "/work/app"])
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configFile.path))
        #expect(runner.recorded.isEmpty)
    }

    @Test func onlyAnExistingAbsoluteFolderCanBePinnedOrRevealed() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let runner = FakeProcessRunner()
        let actions = machine.actions(runner, directories: ["/work\0suffix"], files: ["/work/script.command"])
        for path in ["/work/missing", "/work/script.command", "work/relative", "", "/work\0suffix"] {
            #expect(await actions.pin(path) == .folderUnavailable(path.withControlCharactersEscaped))
            #expect(await actions.revealFolder(path) == .folderUnavailable(path.withControlCharactersEscaped))
        }
        #expect(!FileManager.default.fileExists(atPath: machine.paths.stateFile.path))
        #expect(runner.recorded.isEmpty)
    }

    @Test func revealCarriesTheWholeFolderAsOneArgumentAndNeverOpensItsDefaultApp() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let folder = "/work/it's a \"folder\"; $(touch sentinel)\nsecond line"
        let runner = FakeProcessRunner()
        #expect(await machine.actions(runner, directories: [folder]).revealFolder(folder) == nil)
        #expect(runner.recorded == [ProcessStep(executable: "/usr/bin/open", arguments: ["-R", folder])])
        #expect(!FileManager.default.fileExists(atPath: machine.paths.stateFile.path))
    }

    @Test func aFailedRevealReportsTheProcessErrorAndKeepsTheSavedFolder() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try seed(machine)
        let runner = FakeProcessRunner(results: [ProcessResult(status: 1, standardError: "Finder could not show the folder.")])
        #expect(await machine.actions(runner, directories: ["/work/app"]).revealFolder("/work/app") == .failed("Finder could not show the folder."))
        #expect(try StateStore.load(paths: machine.paths).pins == ["/work/app", "/work/web"])
    }

    @Test func aPinThatCannotBeSavedReturnsAnError() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try seed(machine)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: machine.paths.configDirectory.path)
        let notice = await machine.actions(FakeProcessRunner(), directories: ["/work/new"]).pin("/work/new")
        #expect(notice?.isProblem == true)
        #expect(try StateStore.load(paths: machine.paths).pins == ["/work/app", "/work/web"])
    }

    @Test func aPinGoesAndTheOthersStay() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try seed(machine)
        #expect(await machine.actions(FakeProcessRunner()).unpin("/work/app") == nil)
        let state = try StateStore.load(paths: machine.paths)
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
        let state = try StateStore.load(paths: machine.paths)
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
        #expect(try StateStore.load(paths: machine.paths).recents == ["/work/notes", "/work/app"], "the window must not claim a clear that did not happen")
    }
}
