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

@Suite("SetupActions: changing the config from the window")
struct SetupActionsConfigEditTests {
    private let list = "[menu]\nitems = [\"open-terminal\", \"-\", \"copy-path\"]\n"

    @Test func aChangeIsMadeInTheFileThatDecidesTheKeyAndCanBeTakenBack() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        try list.write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        let actions = machine.actions(FakeProcessRunner())
        let edited = await actions.editConfig([.move(from: 3, to: 1, in: "menu.items")], deciding: "menu.items")
        #expect(edited.notice == nil && edited.change?.written == true && edited.change?.target == .shared)
        #expect(try String(contentsOf: machine.paths.configFile, encoding: .utf8) == "[menu]\nitems = [\"copy-path\", \"open-terminal\", \"-\"]\n")
        #expect(ConfigService(paths: machine.paths).history().map(\.actor) == [.window])
        let undone = await actions.undoConfigEdit(target: edited.change?.target ?? .shared)
        #expect(undone.notice == nil && undone.change?.written == true)
        #expect(try String(contentsOf: machine.paths.configFile, encoding: .utf8) == list)
    }

    @Test func theMachinesOwnFileIsChangedWhenItSetsTheKey() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        try list.write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        try "[menu]\nitems = [\"copy-path\", \"open-editor\"]\n".write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        let actions = machine.actions(FakeProcessRunner())
        let edited = await actions.editConfig([.remove(at: 1, from: "menu.items")], deciding: "menu.items")
        #expect(edited.change?.target == .local)
        #expect(try String(contentsOf: machine.paths.localConfigFile, encoding: .utf8) == "[menu]\nitems = [\"open-editor\"]\n")
        #expect(try String(contentsOf: machine.paths.configFile, encoding: .utf8) == list)
        #expect((await actions.undoConfigEdit(target: edited.change?.target ?? .shared)).change?.target == .local)
    }

    @Test func aSettingThatThisMacsFileSetAndTheChangeTookOutIsTakenBackInThatFile() async throws {
        // After the change the key is not in this Mac's file any more, so the file that decides it now is the shared one: Undo goes to the file the change was made in.
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        try "[general]\nagents = [\"claude\"]\n".write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        let overlay = "[agent.claude]\nterminal = \"terminal\"\nargs = [\"-v\"]\n"
        try overlay.write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        let actions = machine.actions(FakeProcessRunner())
        let edited = await actions.editConfig([.unset("agent.claude.terminal")], deciding: "agent.claude.terminal")
        #expect(edited.change?.target == .local && edited.change?.written == true)
        #expect(await actions.owner(of: "agent.claude.terminal") == .shared, "the key has moved to the shared file's side")
        let undone = await actions.undoConfigEdit(target: .local, expecting: edited.change?.afterDigest)
        #expect(undone.notice == nil && undone.change?.written == true)
        #expect(try String(contentsOf: machine.paths.localConfigFile, encoding: .utf8) == overlay)
        let again = await actions.undoConfigEdit(target: .local, expecting: edited.change?.afterDigest)
        #expect(again.notice?.isProblem == true, "and only once")
    }

    @Test func aFileThatSomeoneElseChangedAndChangedBackIsNotTheChangeThatWasMade() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        let one = "[[preset]]\nid = \"mine\"\ntitle = \"One\"\nprompt = \"Look at {files}.\"\n"
        try one.write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        let actions = machine.actions(FakeProcessRunner())
        let edited = await actions.editConfig([.set("preset.1.title", .string("Two"))], deciding: "preset.mine")
        let change = try #require(edited.change)
        // An assistant sets another title and then the one the window wrote: the text is the window's again, and the last edit is the assistant's.
        let service = ConfigService(paths: machine.paths)
        _ = try service.apply(.set("preset.1.title", .string("Three")), actor: .mcp)
        _ = try service.apply(.set("preset.1.title", .string("Two")), actor: .mcp)
        let refused = await actions.undoConfigEdit(target: .shared, expecting: change.afterDigest, replacing: change.beforeDigest)
        #expect(refused.change == nil && refused.notice == .undoRefused, "the title is still Two and Three is not brought back as if it were the first")
        #expect(try String(contentsOf: machine.paths.configFile, encoding: .utf8).contains("title = \"Two\""))
        // Held to the after digest alone, which is all it knew, the same text is taken for the change: that is what the second digest is for.
        let alone = await actions.undoConfigEdit(target: .shared, expecting: change.afterDigest)
        #expect(alone.change?.written == true)
    }

    @Test func aKeyOfAnAgentOfOnesOwnGoesToTheFileThatMakesItsTable() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        try "[general]\nagents = [\"claude\"]\n".write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        try "[general]\nagents = [\"claude\", \"mine\"]\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n".write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        let actions = machine.actions(FakeProcessRunner())
        #expect(await actions.owner(of: "agent.mine.terminal") == .shared, "the overlay does not write it yet")
        #expect(await actions.owner(of: "agent.mine.terminal", anchor: "agent.mine.command") == .local)
        let edited = await actions.editConfig([.set("agent.mine.terminal", .string("terminal"))], deciding: "agent.mine.terminal", anchor: "agent.mine.command")
        #expect(edited.notice == nil && edited.change?.target == .local && edited.change?.written == true)
        let refused = await actions.editConfig([.set("agent.mine.args", .strings(["-v"]))], deciding: "agent.mine.args")
        #expect(refused.change == nil && refused.notice?.isProblem == true, "in the shared file that is a table with no name and no command")
    }

    @Test func aChangeThatLeavesThisMacsFileNamingWhatItTookOutIsRefused() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let shared = "[general]\nagents = [\"claude\", \"mine\"]\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n"
        let overlay = "[agent.mine]\nterminal = \"terminal\"\n"
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        try shared.write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        try overlay.write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        let actions = machine.actions(FakeProcessRunner())
        let removal: [ConfigOperation] = [.remove(at: 2, from: "general.agents"), .removeTable("agent.mine")]
        let refused = await actions.editConfig(removal, deciding: "general.agents")
        #expect(refused.change == nil && refused.notice?.isProblem == true)
        if case .failed(let text)? = refused.notice { #expect(text.contains("needs name and command") && text.contains("config.local.toml"), "\(text)") }
        #expect(try String(contentsOf: machine.paths.configFile, encoding: .utf8) == shared, "nothing was written, and the config still reads")
        #expect(ConfigStore.load(paths: machine.paths).result.hasErrors == false)
    }

    @Test func aPresetIsWhereTheFileThatHoldsItWritesItAndItsIdIsInUseWhetherOrNotItIsShown() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        let entry = { (id: String) in "[[preset]]\nid = \"\(id)\"\ntitle = \"\(id)\"\nprompt = \"Look at {files}.\"\n\n" }
        try (entry("a") + entry("b")).write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        try (entry("b") + entry("c") + "[[preset]]\nid = \"broken\"\ntitle = \"x\"\nprompt = \"-no\"\n").write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        let service = ConfigService(paths: machine.paths)
        #expect(service.presetEntries() == ["a": PresetRowState.Entry(target: .shared, position: 1), "b": PresetRowState.Entry(target: .local, position: 1),
                                            "c": PresetRowState.Entry(target: .local, position: 2), "broken": PresetRowState.Entry(target: .local, position: 3)],
                "the same place of the two files is two presets, and an entry of this Mac's file replaces the shared one of its id")
        #expect(service.presetIDsInUse() == ["a", "b", "c", "broken"], "an entry that the config leaves out for an error still has its id")
        #expect(await machine.actions(FakeProcessRunner()).presetIDsInUse() == service.presetIDsInUse())
    }

    @Test func theIdsOfEveryFileAndTheOnesThisMacTurnsOffAreInUse() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        try "[agent.foo]\nname = \"Foo\"\ncommand = \"foo\"\n\n[[agent.bar.variant]]\nid = \"x\"\ntitle = \"X\"\narguments = []\n".write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        try "disabled = [\"foo\", \"zed\"]\n\n[agent.baz]\nname = \"Baz\"\ncommand = \"baz\"\n".write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        #expect(await machine.actions(FakeProcessRunner()).agentIDsInUse() == ["foo", "bar", "baz", "zed"])
    }

    @Test func aRefusedChangeIsANoticeInTheConfigsOwnWordsAndTheFileIsLeftAlone() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        try "[menu\n".write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        let result = await machine.actions(FakeProcessRunner()).editConfig([.remove(at: 1, from: "menu.items")], deciding: "menu.items")
        #expect(result.change == nil && result.notice?.isProblem == true)
        if case .failed(let text)? = result.notice { #expect(text.hasPrefix("The config cannot be edited as it is:"), "\(text)") }
        #expect(try String(contentsOf: machine.paths.configFile, encoding: .utf8) == "[menu\n")
        let nothing = await machine.actions(FakeProcessRunner()).undoConfigEdit(target: .shared)
        #expect(nothing.notice?.isProblem == true && nothing.change == nil)
    }

    @Test func withNoConfigThereIsNothingToChange() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let result = await machine.actions(FakeProcessRunner()).editConfig([.insert("copy-path", into: "menu.items", at: nil)], deciding: "menu.items")
        #expect(result.change == nil && result.notice?.isProblem == true)
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configFile.path), "a first run is not skipped by an edit")
    }
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
