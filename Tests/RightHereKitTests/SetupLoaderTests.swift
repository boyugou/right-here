import Foundation
import Synchronization
import Testing
import RightHereCore
@testable import RightHereKit

/// A throwaway home with a config folder in it. Nothing outside it is touched, and no process is started.
private struct Machine {
    let home: URL
    let paths: RHPaths
    let ghostty = URL(fileURLWithPath: "/Applications/Ghostty.app")
    let vscode = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")

    init() throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }

    var facts: FakeSystemFacts {
        FakeSystemFacts(homeDirectory: home, directories: [home.path],
                        applications: ["com.mitchellh.ghostty": ghostty, "com.microsoft.VSCode": vscode])
    }

    func writeConfig(_ text: String) throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try text.write(to: paths.configFile, atomically: true, encoding: .utf8)
    }

    func loader(runner: any ProcessRunner) -> SetupLoader {
        SetupLoader(facts: facts, paths: paths, runner: runner, helperPath: "/opt/rh/bin/rh", localizer: .english, finderShowsSeparators: true)
    }
}

private let pluginkitEnabled = "+    \(AppIdentity.extensionBundleID)(1.0)\tU1\t2026-10-11 23:29:41 +0000\t/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex\n"

/// Remembers whether each question about the machine was asked on the main thread. The questions the loader asks of the
/// facts are plain calls made in its own body, so they say where the body runs; a process runner would not (an `async`
/// function that is not isolated hops off the main actor by itself).
private final class ThreadProbeFacts: SystemFacts, Sendable {
    private let base: FakeSystemFacts
    private let asked = Mutex<[Bool]>([])

    init(_ base: FakeSystemFacts) { self.base = base }

    var onMainThread: [Bool] { asked.withLock { $0 } }
    private func note() { asked.withLock { $0.append(pthread_main_np() != 0) } }

    var homeDirectory: URL { note(); return base.homeDirectory }
    var currentDirectory: URL { base.currentDirectory }
    var loginShell: String { base.loginShell }
    func isDirectory(_ url: URL) -> Bool? { note(); return base.isDirectory(url) }
    func fileExists(_ url: URL) -> Bool { note(); return base.fileExists(url) }
    func itemState(_ url: URL) -> ItemState { base.itemState(url) }
    func gitRoot(containing url: URL) -> URL? { base.gitRoot(containing: url) }
    func applicationURL(bundleID: String) -> URL? { note(); return base.applicationURL(bundleID: bundleID) }
    func displayName(bundleID: String) -> String? { note(); return base.displayName(bundleID: bundleID) }
    func bundleVersion(bundleID: String) -> String? { base.bundleVersion(bundleID: bundleID) }
    func isRunning(bundleID: String) -> Bool { base.isRunning(bundleID: bundleID) }
    func environment(_ key: String) -> String? { base.environment(key) }
    func onDiskPath(_ url: URL) -> String { base.onDiskPath(url) }
}

@Suite("SetupLoader")
struct SetupLoaderTests {
    @Test func readsTheChecksTheMenuAndTheFoldersInOnePass() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = []\n")
        try StateStore(pins: ["/Users/tester/Projects/app"], recents: ["/Users/tester/Projects/web", "/Users/tester/Notes"]).save(paths: machine.paths)

        let snapshot = await machine.loader(runner: FakeProcessRunner(results: [ProcessResult(status: 0), ProcessResult(status: 0, standardOutput: pluginkitEnabled)])).load()

        #expect(snapshot.checks.first?.id == .config)
        #expect(snapshot.checks.first { $0.id == .terminalDefault }?.openedApp == "Ghostty")
        #expect(snapshot.checks.first { $0.id == .finderExtension }?.status == .ok)
        #expect(snapshot.folders.pins == ["/Users/tester/Projects/app"])
        #expect(snapshot.folders.recents == ["/Users/tester/Projects/web", "/Users/tester/Notes"])
        #expect(snapshot.configFile == machine.paths.configFile)
        #expect(snapshot.configProblems.isEmpty)
        #expect(!snapshot.configHasErrors)
        let config = ConfigStore.load(paths: machine.paths)
        #expect(snapshot.menu == MenuPreview.folderMenu(config.result, facts: machine.facts, folder: machine.home, localizer: .english))
        #expect(!snapshot.menu.isEmpty)
    }

    @Test func theMenuEditorIsInTheSnapshotAndIsReadAgainWithoutTheDoctor() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[menu]\nitems = [\"open-terminal\", \"-\", \"copy-path\"]\n")
        let runner = FakeProcessRunner()
        let loader = machine.loader(runner: runner)
        let snapshot = await loader.load()
        let editor = try #require(snapshot.menuEditor)
        #expect(editor.rows.map(\.entry) == ["open-terminal", "-", "copy-path"] && !editor.usesDefaults)
        #expect(snapshot.menuTarget == .shared)
        let calls = runner.recorded.count
        let again = await loader.menu()
        #expect(again.editor == editor && again.menu == snapshot.menu && again.target == .shared && again.problems.isEmpty)
        #expect(runner.recorded.count == calls, "the doctor (and with it the login shell) is not asked for what an edit shows")
        // Another edit, made by hand meanwhile, is what the next read says.
        try machine.writeConfig("[menu]\nitems = [\"copy-path\"]\n")
        #expect(await loader.menu().editor?.rows.map(\.entry) == ["copy-path"])
    }

    @Test func theMenuTheWindowShowsHasNoSeparatorsWhereFinderWouldDrawThemAsEmptyRows() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nterminal = \"ghostty\"\nagents = []\n[menu]\nitems = [\"open-terminal\", \"-\", \"open-with\", \"-\", \"copy-path\"]\n")
        func separators(_ nodes: [MenuNode]) -> Int { nodes.reduce(0) { $0 + ($1.kind == .separator ? 1 : 0) + separators($1.children) } }
        let with = await SetupLoader(facts: machine.facts, paths: machine.paths, runner: FakeProcessRunner(), helperPath: "/opt/rh/bin/rh", localizer: .english, finderShowsSeparators: true).menu()
        let without = await SetupLoader(facts: machine.facts, paths: machine.paths, runner: FakeProcessRunner(), helperPath: "/opt/rh/bin/rh", localizer: .english, finderShowsSeparators: false).menu()
        #expect(separators(with.menu) >= 2, "there are separators in the menu, and one inside Open With")
        #expect(separators(without.menu) == 0)
        func titles(_ nodes: [MenuNode]) -> [String] { nodes.filter { $0.kind != .separator }.flatMap { [$0.title] + titles($0.children) } }
        #expect(titles(without.menu) == titles(with.menu), "only the separators are gone")
        // What is edited is the config's list, separators included: the rows of the editor are not the preview.
        #expect(without.editor?.rows.map(\.entry) == ["open-terminal", "-", "open-with", "-", "copy-path"])
    }

    @Test func aConfigThatCannotBeEditedHasNoEditorAndOneThatIsNotThereHasNone() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let loader = machine.loader(runner: FakeProcessRunner())
        #expect(await loader.menu().editor == nil, "a config is made by the setup, not by an edit")
        try machine.writeConfig("[menu\nitems = []\n")
        let broken = await loader.menu()
        #expect(broken.editor == nil && broken.menu.isEmpty && broken.problems.first?.severity == .error)
        try machine.writeConfig("[general]\nterminal = \"nonsense\"\n")
        #expect(await loader.menu().editor == nil, "a config with an error in a value as well")
        #expect(await loader.load().menuEditor == nil)
    }

    @Test func everyEditorIsThereForAConfigThatCanBeEditedAndNoneForOneThatCannot() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n\n[[agent.claude.variant]]\nid = \"opus\"\ntitle = \"Use Opus\"\narguments = [\"--model\", \"opus\"]\n")
        let loader = machine.loader(runner: FakeProcessRunner())
        let editable = await loader.menu()
        #expect(editable.editor != nil && editable.general != nil && editable.presets != nil && editable.newFile != nil && editable.agentOptions.contains { $0.id == "claude" })
        let variants = editable.agentOptions.first { $0.id == "claude" }?.variants
        #expect(variants?.map(\.id) == ["opus"] && variants?.first?.entry == EntryLocation(target: .shared, position: 1) && variants?.first?.arguments.listed == ["--model", "opus"], "the places and the listed arguments of the start options")
        try machine.writeConfig("[general]\nterminal = \"nonsense\"\n")
        let broken = await loader.menu()
        #expect(broken.editor == nil && broken.general == nil && broken.presets == nil && broken.newFile == nil && broken.agentOptions.isEmpty)
    }

    @Test func theMachinesOwnFileIsWhereTheMenuIsEditedWhenItListsTheMenu() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[menu]\nitems = [\"open-terminal\"]\n")
        let loader = machine.loader(runner: FakeProcessRunner())
        #expect(await loader.menu().target == .shared)
        try "[menu]\nitems = [\"copy-path\", \"open-editor\"]\n".write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        let shown = await loader.menu()
        #expect(shown.target == .local && shown.editor?.rows.map(\.entry) == ["copy-path", "open-editor"], "what decides here is what is shown")
        // An overlay that does not list the menu leaves it to the shared file.
        try "[general]\nterminal = \"ghostty\"\n".write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        #expect(await loader.menu().target == .shared)
    }

    @Test func aMachineWithNothingSetUpStillAnswers() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let snapshot = await machine.loader(runner: FakeProcessRunner()).load()
        #expect(!snapshot.checks.isEmpty)
        #expect(snapshot.folders.pins.isEmpty && snapshot.folders.recents.isEmpty)
        #expect(snapshot.configProblems.isEmpty)
    }

    @Test func aConfigWithErrorsHasNoMenuAndSaysWhatIsWrong() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general\nterminal = \"ghostty\"\n")
        let snapshot = await machine.loader(runner: FakeProcessRunner()).load()
        #expect(snapshot.menu.isEmpty)
        #expect(snapshot.configHasErrors)
        #expect(snapshot.configProblems.first?.severity == .error)
        #expect(snapshot.configProblems.first?.summary(file: snapshot.configFile).hasPrefix("error: config.toml") == true)
        #expect(snapshot.checks.first { $0.id == .config }?.status == .fail)
    }

    @Test func aWarningIsAProblemButTheMenuIsStillThere() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nterminal = \"ghostty\"\nunknown_setting = 1\n")
        let snapshot = await machine.loader(runner: FakeProcessRunner()).load()
        #expect(snapshot.configProblems.contains { $0.severity == .warning })
        #expect(!snapshot.configHasErrors)
        #expect(!snapshot.menu.isEmpty)
    }

    @Test func theLoginShellIsAskedOncePerLoadAndGitNever() async throws {
        // The window's refresh used to read the config three times and run `git worktree list` as well; the shell is the
        // slow part (it runs the person's startup files), so it may be started once and only for the agents.
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nagents = [\"claude\"]\n")
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "\nclaude\u{01}/usr/local/bin/claude\n"), ProcessResult(status: 0, standardOutput: pluginkitEnabled)])
        _ = await machine.loader(runner: runner).load()
        #expect(runner.recorded.map(\.executable) == ["/bin/zsh", "/usr/bin/pluginkit"])
    }

    @Test func withNoAgentInTheMenuTheShellIsStillAskedOnceAboutEveryAgent() async throws {
        // The Agents page says which agents a terminal would find, to choose from: that is most useful when none is chosen yet.
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nagents = []\n")
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "\ncodex\u{01}/opt/codex\n"), ProcessResult(status: 0, standardOutput: pluginkitEnabled)])
        let snapshot = await machine.loader(runner: runner).load()
        #expect(runner.recorded.map(\.executable) == ["/bin/zsh", "/usr/bin/pluginkit"])
        #expect(snapshot.agentCommands?.locations == ["codex": "/opt/codex"])
        #expect(snapshot.agentCommands?.asked.contains("claude") == true)
    }

    @MainActor
    @Test func itDoesItsWorkOffTheMainThreadEvenWhenTheCallerIsOnIt() async throws {
        // The doctor starts the login shell and the config and the state are read from disk: a window that did that on its
        // own thread would stop answering while the person's startup files ran.
        #expect(pthread_main_np() != 0)
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        let facts = ThreadProbeFacts(machine.facts)
        let loader = SetupLoader(facts: facts, paths: machine.paths, runner: FakeProcessRunner(), helperPath: nil, localizer: .english)
        _ = await loader.load()
        #expect(!facts.onMainThread.isEmpty)
        #expect(facts.onMainThread.allSatisfy { !$0 })
    }
}

@Suite("Doctor: the launch probe on its own")
struct LaunchProbeAloneTests {
    @Test func itAsksTheExtensionAndNeverTheLoginShell() async throws {
        // After "Test Terminal Launch" the window used to run the whole doctor again with the probe added, which asks the
        // login shell for the agents' commands a second time for a row that is only about the terminal.
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nagents = [\"claude\", \"codex\"]\n")
        try FileManager.default.createDirectory(at: machine.paths.logDirectory, withIntermediateDirectories: true)
        // The probe reads the log for a report newer than its own start; this one is dated ahead of it.
        let when = ISO8601DateFormatter().string(from: Date().addingTimeInterval(30))
        try """
        \(when) probe launch: {"application":"Ghostty","outcome":"ran","seconds":1.2,"accepted":0.4,"shell":"/bin/zsh"}
        """.write(to: machine.paths.logFile, atomically: true, encoding: .utf8)

        let runner = FakeProcessRunner()
        let doctor = Doctor(facts: machine.facts, paths: machine.paths, loaded: ConfigStore.load(paths: machine.paths), runner: runner, rhPath: "/opt/rh/bin/rh")
        let check = await doctor.launchCheck()

        #expect(check.id == .finderLaunch)
        #expect(check.status == .ok)
        #expect(!runner.recorded.contains { $0.executable == "/bin/zsh" })
        #expect(runner.recorded.allSatisfy { $0.executable == "/usr/bin/pluginkit" })
    }
}

@Suite("SetupLoader: the first run")
struct SetupFirstRunTests {
    private struct Mac {
        let home: URL
        let paths: RHPaths

        init() throws {
            home = try makeTemporaryDirectory()
            paths = RHPaths(environment: [:], home: home)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: home) }

        var facts: FakeSystemFacts {
            FakeSystemFacts(homeDirectory: home, directories: [home.path], applications: [
                "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
                "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
                "dev.zed.Zed": URL(fileURLWithPath: "/Applications/Zed.app")
            ])
        }

        func loader(_ runner: any ProcessRunner) -> SetupLoader {
            SetupLoader(facts: facts, paths: paths, runner: runner, helperPath: "/opt/rh/bin/rh", localizer: .english, finderShowsSeparators: true)
        }
    }

    @Test func aMacWithNoConfigOffersWhatIsInstalledAndWhatTheLoginShellFound() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        // The offer asks the login shell once, for the agents; then the doctor asks pluginkit.
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "\ncodex\u{01}/usr/local/bin/codex\n\nclaude\u{01}/usr/local/bin/claude\n")])
        let snapshot = await mac.loader(runner).load()
        #expect(!snapshot.configExists)
        let offer = try #require(snapshot.offer)
        #expect(offer.terminals.map(\.id) == ["ghostty", "terminal"], "installed terminals only, the one a click uses first on top")
        #expect(offer.editors.map(\.id) == ["vscode", "zed"])
        #expect(offer.terminals.first?.icon == .app("com.mitchellh.ghostty"), "an app's chip shows the icon of the copy that is installed")
        #expect(offer.agents.allSatisfy { $0.icon == nil })
        #expect(offer.agents.map(\.id).prefix(2) == ["claude", "codex"], "the agents that were found come first, in Right Here's order")
        #expect(offer.agents.filter(\.available).map(\.id) == ["claude", "codex"])
        #expect(Set(offer.agents.map(\.id)) == Set(KnownAgents.all.map(\.id)), "every agent Right Here knows can be chosen")
        #expect(offer.detected == DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude", "codex"]))
        #expect(runner.recorded.filter { $0.arguments.first == "-lic" }.count == 1, "the person's startup files ran more than once for the first window")
    }

    @Test func theOfferSaysWhetherTheLoginShellAnswered() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        let silent = await mac.loader(FakeProcessRunner(results: [ProcessResult(status: 1)])).load()
        #expect(silent.offer?.loginShellAnswered == false, "a shell that printed nothing, not even the end of the script, did not say there is no agent")
        #expect(silent.offer?.agents.allSatisfy { !$0.available } == true)
        let answered = await mac.loader(FakeProcessRunner(results: [ProcessResult(status: 1, standardOutput: "\nclaude\u{01}/usr/local/bin/claude\n\u{01}rh-done\u{01}\n")])).load()
        #expect(answered.offer?.loginShellAnswered == true)
        let none = await mac.loader(FakeProcessRunner(results: [ProcessResult(status: 1, standardOutput: "\u{01}rh-done\u{01}\n")])).load()
        #expect(none.offer?.loginShellAnswered == true && none.offer?.agents.allSatisfy { !$0.available } == true, "a shell that answered that there is none")
    }

    @Test func withAConfigThereIsNothingToOffer() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try FileManager.default.createDirectory(at: mac.paths.configDirectory, withIntermediateDirectories: true)
        try "[general]\nagents = []\n".write(to: mac.paths.configFile, atomically: true, encoding: .utf8)
        let runner = FakeProcessRunner()
        let snapshot = await mac.loader(runner).load()
        #expect(snapshot.configExists && snapshot.offer == nil)
        #expect(runner.recorded.filter { $0.executable == "/bin/zsh" }.count == 1, "a login shell is started for the doctor alone, and none to offer what nobody needs")
    }

    @Test func aPerMachineOverlayAloneIsAConfig() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try FileManager.default.createDirectory(at: mac.paths.configDirectory, withIntermediateDirectories: true)
        try "[general]\nterminal = \"terminal\"\n".write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8)
        let snapshot = await mac.loader(FakeProcessRunner()).load()
        #expect(snapshot.configExists && snapshot.offer == nil)
    }

    @Test func theChoicesAreWhatIsCheckedInTheOrderRightHereListsTheAgents() {
        let offer = SetupOffer()
        let choices = offer.choices(terminal: "terminal", editor: nil, agents: ["codex", "claude", "aider"])
        #expect(choices == SetupChoices(terminal: "terminal", editor: nil, agents: ["claude", "codex", "aider"]))
        #expect(offer.choices(terminal: nil, editor: nil, agents: []).agents == [], "nothing checked is a choice: no agents")
    }
}

@Suite("SetupLoader: the editors show what the merged config shows, and write where it is written")
struct SetupLoaderEntryTests {
    private let both = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\", \"codex\"]\n"

    private func menu(_ machine: Machine, local: String? = nil) async throws -> MenuSnapshot {
        if let local { try local.write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8) }
        return await machine.loader(runner: FakeProcessRunner()).menu()
    }

    @Test func aPresetThatThisMacTurnsOffIsNotTheEntryOfTheRowThatTakesItsPlace() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(both + "\n[[preset]]\nid = \"review\"\ntitle = \"Strict review\"\nprompt = \"Review {files} strictly.\"\nagent = \"codex\"\n")
        let shown = try await menu(machine, local: "disabled = [\"codex\"]\n")
        let row = try #require(shown.presets?.row(id: "review"))
        #expect(row.origin == .builtIn && row.entry == nil && row.title == "Review", "this Mac shows the built-in preset, so that is what the window edits")
        #expect(PresetOptions.changing(title: "x", of: row) == nil && PresetOptions.removing(row) == nil)
        #expect(shown.presets?.agents.map(\.id).contains("codex") == false && shown.presets?.agents.map(\.id).contains("claude") == true, "an agent this Mac turns off is not offered for a preset")
    }

    @Test("an id written as a multi-line string, a literal string or with an escape is the id the parser reads", arguments: ["\"\"\"mine\"\"\"", "'''mine'''", "'mine'", "\"m\\u0069ne\""])
    func anIdIsReadAsTheParserReadsIt(spelling: String) async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(both + "\n[[preset]]\nid = \"mine\"\ntitle = \"Shared\"\nprompt = \"Look at {files}.\"\n")
        let shown = try await menu(machine, local: "[[preset]]\nid = \(spelling)\ntitle = \"Local\"\nprompt = \"Read {files}.\"\n")
        let row = try #require(shown.presets?.row(id: "mine"))
        #expect(row.title == "Local" && row.entry == EntryLocation(target: .local, position: 1), "the entry of the file that decides here, not the shared one (\(spelling))")
        let ids = ConfigService(paths: machine.paths).entryIDsInUse(of: "preset")
        #expect(ids == ["mine"])
    }

    @Test func aTemplateThisMacTurnsOffLeavesTheOtherBuiltInOnesBuiltInAndTheFirstNewTemplateWritesThemAllOut() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(both)
        let shown = try await menu(machine, local: "disabled = [\"md\"]\n")
        let state = try #require(shown.newFile)
        #expect(state.isBuiltIn && state.rows.map(\.id) == ["txt", "docx", "xlsx", "pptx"] && state.seed.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx"],
                "the config defines no template, and this Mac does not show one of the built-in ones")
        let made = try #require(NewFileOptions.creating(title: "Python Script", fileExtension: "py", in: state))
        let written = made.change.operations.compactMap { operation -> String? in
            if case .addEntry(_, let fields, _) = operation { fields.first { $0.key == "id" }.map { "\($0.value)" } } else { nil }
        }
        #expect(written.count == 6 && made.id == "python-script", "every built-in template is written out, the one this Mac turns off included: the shared file is read by Macs that do not turn it off")
        #expect(NewFileOptions.creating(title: "Markdown", fileExtension: "md", in: state)?.id == "markdown", "a title that slugs to a built-in id is not that id")
        #expect(NewFileOptions.creating(title: "md", fileExtension: "md", in: state)?.id == "md-2", "and neither is a built-in id the window does not show")
    }

    @Test func theIdsThisMacTurnsOffAreInUseForANewEntry() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(both + "\n[[new_file.template]]\nid = \"notes\"\ntitle = \"Notes\"\nextension = \"txt\"\n")
        try "disabled = [\"python\", \"codex\"]\n".write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        #expect(ConfigService(paths: machine.paths).entryIDsInUse(of: "new_file.template") == ["notes", "python", "codex"])
    }

    @Test func theAppsTheConfigAddsAreLinesWithTheFileThatHoldsEachAndThereAreNoneWhileTheConfigHasAnError() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(both + "\n[[app]]\nid = \"pulsar\"\nname = \"Pulsar\"\nbundle_id = \"dev.pulsar-edit.pulsar\"\nrole = \"editor\"\n")
        let shown = try await menu(machine, local: "[[app]]\nid = \"nova\"\nname = \"Nova Editor\"\nbundle_id = \"com.example.NovaEditor\"\n")
        let apps = try #require(shown.apps)
        #expect(apps.rows.map(\.id).sorted() == ["nova", "pulsar"])
        #expect(apps.row(id: "pulsar")?.entry == EntryLocation(target: .shared, position: 1) && apps.row(id: "nova")?.entry == EntryLocation(target: .local, position: 1))
        #expect(apps.available["dev.pulsar-edit.pulsar"] == "Pulsar" && apps.available["com.mitchellh.ghostty"] == "Ghostty", "what is offered already, built in or added")
        try machine.writeConfig("[general\nterminal = ")
        #expect(try await menu(machine).apps == nil, "a config that does not read cannot be edited")
    }

    @Test func aPresetWrittenAsAnInlineArrayIsTheConfigsOwnAndHasNoPlaceToEdit() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("preset = [{ id = \"mine\", title = \"Mine\", prompt = \"Look at {files}.\" }]\n\n" + both)
        let row = try #require(try await menu(machine).presets?.row(id: "mine"))
        #expect(row.origin == .own && row.entry == nil, "it is not the built-in preset, and the window cannot change it by place")
        #expect(PresetOptions.changing(title: "x", of: row) == nil)
    }

    @Test func anIdThatIsWrittenInAnInlineListIsInUseAndAListWrittenAsAValueGetsNoEntryAppended() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("preset = [{ id = \"zed\", title = \"Zed\", prompt = \"Look at {files}.\", agent = \"codex\" }]\n\n" + both)
        try "disabled = [\"codex\"]\n".write(to: machine.paths.localConfigFile, atomically: true, encoding: .utf8)
        let ids = ConfigService(paths: machine.paths).entryIDsInUse(of: "preset")
        #expect(ids.contains("zed") && ids.contains("codex"), "an inline entry that the config does not show is still in use: \(ids)")
        let shown = try await menu(machine)
        #expect(shown.presets?.row(id: "zed") == nil, "it is dropped here")
        #expect(throws: ConfigDocument.EditError.self) { try ConfigDocument(try String(contentsOf: machine.paths.configFile, encoding: .utf8)).addingEntry(to: "preset", fields: [("id", .string("x")), ("title", .string("X")), ("prompt", .string("Look at {files}."))]) }
    }

    /// Reading the entries once for each entry made the time grow with the square of their number. A time limit failed on a busy machine whatever the code
    /// was, so the test compares ten times the entries with the time they take: about ten times as long when the reading is done a few times, about a
    /// hundred times when it is done once for each entry. The faster of two runs counts, which leaves out a moment when the machine was busy.
    @Test func theEntriesOfALargeConfigAreReadInAFewReadingsAndNotOneForEachEntry() async throws {
        func time(presets count: Int) async throws -> Duration {
            let machine = try Machine(); defer { machine.cleanUp() }
            var text = both
            for index in 1...count { text += "\n[[preset]]\nid = \"p\(index)\"\ntitle = \"Preset \(index)\"\nprompt = \"Look at {files} (\(index)).\"\n" }
            try machine.writeConfig(text)
            var fastest = Duration.seconds(3600)
            for _ in 0..<2 {
                let started = ContinuousClock.now
                let shown = try await menu(machine)
                fastest = min(fastest, started.duration(to: .now))
                #expect(shown.presets?.rows.filter { $0.origin == .own }.count == count)
            }
            return fastest
        }
        let few = try await time(presets: 30), many = try await time(presets: 300)
        #expect(many < few * 40, "30 presets took \(few), 300 took \(many): the time grows faster than the number of entries")
    }
}
