import Foundation
import Synchronization
import Testing
import RightHereCore
@testable import RightHereKit

/// A machine for one run of setup: a throwaway home, facts that say which apps are installed, and a runner that answers for the
/// login shell, `pluginkit` (which remembers what was registered) and `pbs`, and writes down every process it was asked to start.
private final class Machine: Sendable {
    let home: URL
    let paths: RHPaths
    let rh: String
    let app: URL
    /// What the login shell prints when it is asked which agent commands it finds.
    let shellOutput: String
    /// Whether the login shell gets to the end of its script (the last line it prints); a startup file that exits does not.
    let shellAnswers: Bool

    private struct State {
        var registered: [String] = []
        var enabled = false
        var steps: [ProcessStep] = []
    }

    private let state = Mutex(State())

    init(shellOutput: String = "\nclaude\u{01}/usr/local/bin/claude\n\ncodex\u{01}/usr/local/bin/codex\n", shellAnswers: Bool = true, registered: [String] = [], enabled: Bool = false) throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
        self.shellOutput = shellOutput
        self.shellAnswers = shellAnswers
        rh = home.appendingPathComponent("tools/rh").path
        app = home.appendingPathComponent("Applications/Right Here.app")
        try FileManager.default.createDirectory(at: HostApp.extensionURL(in: app), withIntermediateDirectories: true)
        state.withLock { $0.registered = registered; $0.enabled = enabled }
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }

    var appex: String { HostApp.extensionURL(in: app).path }

    var facts: FakeSystemFacts {
        FakeSystemFacts(homeDirectory: home, directories: [home.path],
                        applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
                                       "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
                                       "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")],
                        variables: ["PATH": "/usr/bin:/bin"])
    }

    var recorded: [ProcessStep] { state.withLock { $0.steps } }
    var registered: [String] { state.withLock { $0.registered } }
    var enabled: Bool { state.withLock { $0.enabled } }

    /// The processes that change something on the Mac: `pluginkit` with anything but a listing, and `pbs`.
    var mutations: [String] {
        recorded.compactMap { step in
            if step.executable == "/usr/bin/pluginkit", step.arguments.first != "-m" { return "pluginkit " + step.arguments.joined(separator: " ") }
            if step.executable.hasSuffix("/pbs") { return "pbs " + step.arguments.joined(separator: " ") }
            return nil
        }
    }

    var shellStarts: Int { recorded.filter { $0.executable == "/bin/zsh" }.count }

    var processRunner: ProcessRunner {
        ScriptedRunner { [self] step in answer(step) }
    }

    private func answer(_ step: ProcessStep) -> ProcessResult {
        state.withLock { $0.steps.append(step) }
        switch step.executable {
        case "/usr/bin/pluginkit":
            let arguments = step.arguments
            if arguments.first == "-m" {
                return state.withLock { state in
                    ProcessResult(status: 0, standardOutput: state.registered.map {
                        "\(state.enabled ? "+" : "-")    \(AppIdentity.extensionBundleID)(1.0)\tU1\t2026-10-11 23:29:41 +0000\t\($0)\n"
                    }.joined())
                }
            }
            state.withLock { state in
                if arguments.first == "-a", let path = arguments.last { state.registered.append(path) }
                if arguments.first == "-r", let path = arguments.last { state.registered.removeAll { $0 == path } }
                if arguments.starts(with: ["-e", "use"]) { state.enabled = true }
                if arguments.starts(with: ["-e", "ignore"]) { state.enabled = false }
            }
            return ProcessResult(status: 0)
        case "/bin/zsh":
            // The detector and the doctor both ask the login shell; the doctor may also ask for the PATH.
            let wantsPath = step.arguments.contains { $0.contains("rh-path") }
            return ProcessResult(status: 0, standardOutput: shellOutput + (wantsPath ? "\u{01}rh-path\u{01}/usr/bin:/bin\n" : "") + (shellAnswers ? "\u{01}rh-done\u{01}\n" : ""))
        default:
            return ProcessResult(status: 0)
        }
    }

    func runner(app: URL?? = nil, trial: Bool = true, rhPath: String? = nil, lockTimeout: Duration = .seconds(120)) -> SetupRunner {
        SetupRunner(facts: facts, paths: paths, runner: processRunner, rhPath: rhPath ?? rh, app: app ?? self.app,
                    trialHome: trial ? home : nil, localizer: .english, settle: .zero, lockTimeout: lockTimeout)
    }

    func writeConfig(_ text: String, local: String? = nil) throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try text.write(to: paths.configFile, atomically: true, encoding: .utf8)
        if let local { try local.write(to: paths.localConfigFile, atomically: true, encoding: .utf8) }
    }

    var configText: String { (try? String(contentsOf: paths.configFile, encoding: .utf8)) ?? "" }
}

private final class ScriptedRunner: ProcessRunner, Sendable {
    private let handler: @Sendable (ProcessStep) -> ProcessResult

    init(_ handler: @escaping @Sendable (ProcessStep) -> ProcessResult) {
        self.handler = handler
    }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        handler(step)
    }
}

private func outcomes(_ report: SetupReport) -> [String: SetupStep.Outcome] {
    Dictionary(uniqueKeysWithValues: report.steps.map { ($0.piece.rawValue, $0.outcome) })
}

@Suite("Setup: one run puts everything in place")
struct SetupRunnerTests {
    @Test func aFirstRunInATrialHomeMakesEveryPieceAndLeavesTheExtensionToTheWholeMac() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup())
        #expect(report.ok)
        #expect(outcomes(report) == ["config": .created, "runnerScript": .created, "cliLink": .created, "services": .created, "finderExtension": .skipped])
        let installer = Installer(home: machine.home)
        #expect(FileManager.default.fileExists(atPath: machine.paths.configFile.path))
        #expect(installer.runnerScriptIsCurrent(rhPath: machine.rh))
        #expect(installer.existingCLILinkTarget() == machine.rh)
        #expect(!installer.installedServices().isEmpty)
        #expect(machine.mutations.isEmpty, "a trial changed something for the whole Mac: \(machine.mutations)")
        #expect(machine.registered.isEmpty)
        #expect(report.trialHome == machine.home.path)
        #expect(report.warnings.contains { $0.hasPrefix("RH_HOME is set, so this is a trial") })
    }

    @Test func aSetupThatFoundNoAgentBecauseTheLoginShellSaidNothingSaysSo() async throws {
        let machine = try Machine(shellOutput: "", shellAnswers: false); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup(dryRun: true))
        #expect(report.warnings.contains { $0.contains("did not say which AI agents are installed") }, "\(report.warnings)")
        // A person who named the agents has nothing to be told.
        let named = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "ghostty", editor: "vscode", agents: ["claude"]), dryRun: true))
        #expect(!named.warnings.contains { $0.contains("did not say which AI agents are installed") })
    }

    @Test func aShellThatAnsweredAndFoundNothingIsNotSaidToHaveBeenSilent() async throws {
        let machine = try Machine(shellOutput: ""); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup(dryRun: true))
        #expect(!report.warnings.contains { $0.contains("did not say which AI agents are installed") }, "\(report.warnings)")
    }

    @Test func theConfigIsMadeFromWhatIsInstalledAndTheSetupSaysWhatItFound() async throws {
        let machine = try Machine(shellOutput: "\nclaude\u{01}/usr/local/bin/claude\n\ncodex\u{01}/usr/local/bin/codex\n"); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup())
        let chosen = try #require(report.chosen)
        #expect(chosen.terminal == SetupReport.Pick(id: "ghostty", name: "Ghostty", source: .found))
        #expect(chosen.editor == SetupReport.Pick(id: "vscode", name: "Visual Studio Code", source: .found))
        #expect(chosen.agents.map(\.id) == ["claude", "codex"] && chosen.agents.allSatisfy { $0.source == .found })
        let parsed = ConfigParser.parse(machine.configText)
        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.config.terminal == "ghostty" && parsed.config.editor == "vscode" && parsed.config.enabledAgents == ["claude", "codex"])
    }

    @Test func theQuickActionsAreMadeFromTheConfigThatThisRunCreated() async throws {
        // The first `rh install` built them from the config as it was before it existed, so no agent had a Quick Action.
        let machine = try Machine(shellOutput: "\nclaude\u{01}/usr/local/bin/claude\n"); defer { machine.cleanUp() }
        _ = try await machine.runner().run(.setup())
        let names = Installer(home: machine.home).installedServices().map(\.lastPathComponent)
        #expect(names.contains { $0.contains("Claude Code") }, "\(names)")
    }

    // MARK: Idempotence

    @Test func aSecondRunChangesNothingAndSaysSo() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let runner = machine.runner()
        _ = try await runner.run(.setup())
        let before = machine.configText
        let second = try await runner.run(.setup())
        #expect(outcomes(second) == ["config": .unchanged, "runnerScript": .unchanged, "cliLink": .unchanged, "services": .unchanged, "finderExtension": .skipped])
        #expect(machine.configText == before)
        #expect(second.ok)
    }

    @Test func onTheRealMacASecondRunRegistersAndUpdatesNothing() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let runner = machine.runner(trial: false)
        let first = try await runner.run(.setup())
        #expect(outcomes(first)["finderExtension"] == .created)
        #expect(machine.registered == [machine.appex] && machine.enabled)
        #expect(machine.mutations.contains("pbs -update"))
        let mutationsOfTheFirst = machine.mutations.count
        let second = try await runner.run(.setup())
        #expect(outcomes(second) == ["config": .unchanged, "runnerScript": .unchanged, "cliLink": .unchanged, "services": .unchanged, "finderExtension": .unchanged])
        #expect(machine.mutations.count == mutationsOfTheFirst, "the second run changed something: \(machine.mutations.dropFirst(mutationsOfTheFirst))")
    }

    @Test func aRunnerScriptThatPointsAtAnotherRhIsUpdatedAndALinkToAnotherRhIsReplaced() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        _ = try await machine.runner(rhPath: "/old/rh").run(.setup())
        let report = try await machine.runner().run(.setup())
        #expect(outcomes(report)["runnerScript"] == .updated)
        #expect(outcomes(report)["cliLink"] == .updated)
        #expect(outcomes(report)["services"] == .updated)
        #expect(report.step(.cliLink)?.detail?.english().contains("replaced a link to /old/rh") == true)
        #expect(Installer(home: machine.home).installedRunnerTarget() == machine.rh)
    }

    @Test func aQuickActionTheConfigNoLongerAsksForIsRemovedOnTheNextRun() async throws {
        let machine = try Machine(shellOutput: "\nclaude\u{01}/usr/local/bin/claude\n\ncodex\u{01}/usr/local/bin/codex\n"); defer { machine.cleanUp() }
        _ = try await machine.runner().run(.setup())
        try machine.writeConfig("[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = [\"claude\"]\n")
        let report = try await machine.runner().run(.setup())
        #expect(outcomes(report)["services"] == .updated)
        let names = Installer(home: machine.home).installedServices().map(\.lastPathComponent)
        #expect(!names.contains { $0.contains("Codex") }, "\(names)")
    }

    // MARK: Choices

    @Test func whatThePersonSaysIsWrittenAndNothingIsDetectedForIt() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let choices = SetupChoices(terminal: "terminal", editor: "zed", agents: ["claude", "codex"])
        let report = try await machine.runner().run(.setup(choices: choices))
        let parsed = ConfigParser.parse(machine.configText)
        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.config.terminal == "terminal" && parsed.config.editor == "zed" && parsed.config.enabledAgents == ["claude", "codex"])
        let chosen = try #require(report.chosen)
        #expect(chosen.terminal?.source == .you && chosen.editor?.source == .you && chosen.agents.allSatisfy { $0.source == .you })
        // Only the doctor asked the login shell: with all three said there was nothing for the detector to find.
        #expect(machine.shellStarts == 1, "the login shell was started \(machine.shellStarts) times")
    }

    @Test func aChoiceNotMadeIsLeftToTheMachine() async throws {
        let machine = try Machine(shellOutput: "\ncodex\u{01}/usr/local/bin/codex\n"); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup(choices: SetupChoices(editor: "zed")))
        let chosen = try #require(report.chosen)
        #expect(chosen.terminal?.id == "ghostty" && chosen.terminal?.source == .found)
        #expect(chosen.editor?.id == "zed" && chosen.editor?.source == .you)
        #expect(chosen.agents.map(\.id) == ["codex"])
    }

    @Test func noAgentsIsAChoiceToo() async throws {
        let machine = try Machine(shellOutput: "\nclaude\u{01}/usr/local/bin/claude\n\ncodex\u{01}/usr/local/bin/codex\n"); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup(choices: SetupChoices(agents: [])))
        #expect(report.chosen?.agents.isEmpty == true)
        #expect(ConfigParser.parse(machine.configText).config.enabledAgents.isEmpty)
    }

    @Test func anInstalledTerminalThatCannotRunCommandsGetsAWarningWhenAgentsAreChosen() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "warp", agents: ["claude"])))
        #expect(report.warnings.contains { $0.contains("Warp cannot run commands") }, "\(report.warnings)")
    }

    // MARK: A config that is there

    private static let mine = """
    # My own notes.
    version = 1

    [general]
    terminal = "ghostty"   # my favourite
    editor = "vscode"
    agents = ["claude"]

    [menu]
    items = ["open.terminal", "agents"]

    """

    @Test func aConfigThatExistsIsNeverRewrittenAndTheLineToChangeIsGiven() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(Self.mine)
        let report = try await machine.runner().run(.setup(choices: SetupChoices(agents: ["claude", "codex"])))
        #expect(machine.configText == Self.mine, "the config was changed")
        #expect(outcomes(report)["config"] == .unchanged)
        #expect(report.chosen == nil)
        let edit = try #require(report.configEdits.first)
        #expect(report.configEdits.count == 1 && edit.line == 7 && edit.value == "[\"claude\", \"codex\"]")
        #expect(report.warnings.contains { $0.contains("already exists, so Right Here left it alone") })
        #expect(report.next.first?.command == "rh config validate --strict")
        #expect(report.english().contains { $0.contains("In config.toml on line 7, change agents = ⟦user⟧[\"claude\"]⟦/user⟧ to agents = [\"claude\", \"codex\"].") })
    }

    @Test func theEditsComeBeforeTheRealRunSoOneRunBuildsEveryQuickAction() async throws {
        // Persona C of the cold-agent evaluation ran setup, then made the listed edit by hand, and Codex had no Quick Action.
        let machine = try Machine(shellOutput: "\nclaude\u{01}/usr/local/bin/claude\n\ncodex\u{01}/usr/local/bin/codex\n"); defer { machine.cleanUp() }
        try machine.writeConfig(Self.mine)
        let choices = SetupChoices(agents: ["claude", "codex"])
        let dry = try await machine.runner().run(.setup(choices: choices, dryRun: true))
        #expect(dry.configEdits.count == 1)
        #expect(dry.next == [
            SetupNext("rh config validate --strict", why: "After you have made the edits above to the config file: it must say ok, with no error and no warning."),
            SetupNext("rh setup --agents claude,codex", why: "Then the same without --dry-run: it makes the other changes above, and builds the Quick Actions from the config as you edited it.")
        ], "\(dry.next)")
        try machine.writeConfig(Self.mine.replacingOccurrences(of: "agents = [\"claude\"]", with: "agents = [\"claude\", \"codex\"]"))
        let real = try await machine.runner().run(.setup(choices: choices))
        #expect(real.configEdits.isEmpty && real.ok)
        let names = Installer(home: machine.home).installedServices().map(\.lastPathComponent)
        #expect(names.contains { $0.contains("Codex") } && names.contains { $0.contains("Claude Code") }, "\(names)")
    }

    @Test func aRealRunBeforeTheEditsSaysToRunSetupAgainAfterThem() async throws {
        let machine = try Machine(shellOutput: "\nclaude\u{01}/usr/local/bin/claude\n\ncodex\u{01}/usr/local/bin/codex\n"); defer { machine.cleanUp() }
        try machine.writeConfig(Self.mine)
        let first = try await machine.runner().run(.setup(choices: SetupChoices(agents: ["claude", "codex"])))
        #expect(first.next.prefix(2).map(\.command) == ["rh config validate --strict", "rh setup"], "\(first.next.map(\.command))")
        #expect(!Installer(home: machine.home).installedServices().map(\.lastPathComponent).contains { $0.contains("Codex") }, "these Quick Actions came from the file as it was")
        try machine.writeConfig(Self.mine.replacingOccurrences(of: "agents = [\"claude\"]", with: "agents = [\"claude\", \"codex\"]"))
        let again = try await machine.runner().run(.setup())
        #expect(outcomes(again)["services"] == .updated)
        #expect(Installer(home: machine.home).installedServices().map(\.lastPathComponent).contains { $0.contains("Codex") })
    }

    @Test func aConfigThatAlreadySaysWhatWasAskedNeedsNoEditAndNoNote() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(Self.mine)
        let report = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "ghostty", agents: ["claude"])))
        #expect(report.configEdits.isEmpty)
        #expect(!report.warnings.contains { $0.contains("left it alone") })
    }

    @Test func noChoicesOnAnExistingConfigAskForNothing() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(Self.mine)
        let report = try await machine.runner().run(.setup())
        #expect(report.configEdits.isEmpty && machine.configText == Self.mine)
    }

    @Test func forceReplacesTheConfigAfterSavingTheOldOne() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(Self.mine)
        let report = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "terminal", editor: "zed", agents: []), force: true))
        #expect(outcomes(report)["config"] == .updated)
        let backups = try FileManager.default.contentsOfDirectory(atPath: machine.paths.configDirectory.path).filter { $0.hasPrefix("config.toml.bak-") }
        #expect(backups.count == 1)
        #expect(try String(contentsOf: machine.paths.configDirectory.appendingPathComponent(backups[0]), encoding: .utf8) == Self.mine)
        #expect(ConfigParser.parse(machine.configText).config.terminal == "terminal")
        #expect(report.configEdits.isEmpty)
    }

    // MARK: A config that cannot be used

    /// What is in the config file of a person whose config does not parse: a table header that is never closed, on line 2.
    private static let broken = "# mine\n[general\nterminal = \"ghostty\"\n"

    private func writeBytes(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    @Test func aConfigThatDoesNotParseFailsTheConfigStepAndNothingIsMadeOrListedFromIt() async throws {
        let machine = try Machine(shellOutput: "\nclaude\u{01}/usr/local/bin/claude\n\ncodex\u{01}/usr/local/bin/codex\n"); defer { machine.cleanUp() }
        try machine.writeConfig(Self.broken)
        let report = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "terminal", editor: "zed", agents: ["claude", "codex"])))
        #expect(!report.ok)
        // The other steps are not the config's: they still run.
        #expect(outcomes(report) == ["config": .failed, "runnerScript": .created, "cliLink": .created, "services": .skipped, "finderExtension": .skipped])
        let detail = try #require(report.step(.config)?.detail?.english())
        #expect(detail.contains(machine.paths.configFile.path) && detail.contains("line 2: TOML syntax error: table header not closed"), "\(detail)")
        #expect(detail.hasSuffix("so setup left it as it is and made nothing from it"), "\(detail)")
        #expect(machine.configText == Self.broken, "a config is never rewritten")
        #expect(report.configEdits.isEmpty, "edits computed from the defaults for a text that is not TOML: \(report.configEdits.map(\.instruction))")
        #expect(report.chosen == nil)
        #expect(Installer(home: machine.home).installedServices().isEmpty, "Quick Actions were made from the defaults")
        #expect(report.step(.services)?.detail?.english().contains("cannot be used") == true)
        // What the person is told: what and where, that setup left it alone, and that they decide.
        let need = try #require(report.needsUser.first)
        #expect(need.id == .config)
        #expect(need.text.contains(machine.paths.configFile.path) && need.text.contains("line 2") && need.text.contains("left it as it is"), "\(need.text)")
        #expect(need.how.joined().contains("never rewrites") && need.how.joined().contains("tell an AI agent that it may"), "\(need.how)")
        #expect(report.next.map(\.command) == ["rh config validate --strict", "rh setup --terminal terminal --editor zed --agents claude,codex --dry-run"], "\(report.next.map(\.command))")
        // Nothing the doctor would say about the defaults is passed on as if it were the person's.
        #expect(report.checks?.first { $0.id == .config }?.status == .fail)
        #expect(!report.needsUser.contains { $0.id == .automation })
    }

    @Test func aDryRunSaysTheSameOfAConfigThatDoesNotParseAndWritesNothing() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(Self.broken)
        let report = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "terminal"), dryRun: true))
        #expect(!report.ok && report.checks == nil)
        #expect(outcomes(report)["config"] == .failed && outcomes(report)["services"] == .skipped)
        #expect(report.configEdits.isEmpty)
        #expect(report.needsUser.first?.id == .config)
        #expect(report.next.map(\.command) == ["rh config validate --strict", "rh setup --terminal terminal --dry-run"])
        #expect(!FileManager.default.fileExists(atPath: Installer(home: machine.home).runnerScript.path))
        #expect(machine.configText == Self.broken)
    }

    @Test func theQuickActionsThatAreThereStayWhenTheConfigStopsParsing() async throws {
        let machine = try Machine(shellOutput: "\nclaude\u{01}/usr/local/bin/claude\n"); defer { machine.cleanUp() }
        _ = try await machine.runner().run(.setup())
        let installer = Installer(home: machine.home)
        let before = installer.installedServices().map(\.lastPathComponent)
        #expect(!before.isEmpty)
        try machine.writeConfig("[general\n" + machine.configText)
        let again = try await machine.runner().run(.setup())
        #expect(outcomes(again)["services"] == .skipped)
        #expect(installer.installedServices().map(\.lastPathComponent) == before, "the person's Quick Actions were replaced by ones made from the defaults")
    }

    @Test func oneInstallNamedByItselfFailsWhenItsConfigCannotBeUsed() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(Self.broken)
        let report = try await machine.runner().run(SetupRequest(pieces: [.services], strict: true))
        #expect(outcomes(report) == ["services": .failed] && !report.ok)
        #expect(report.step(.services)?.detail?.english().contains("line 2: TOML syntax error") == true)
        #expect(Installer(home: machine.home).installedServices().isEmpty)
        // A piece that does not depend on the config does not say anything about it.
        let scripts = try await machine.runner().run(SetupRequest(pieces: [.runnerScript], strict: true))
        #expect(scripts.ok && scripts.needsUser.isEmpty)
    }

    @Test func anOverlayThatDoesNotParseIsNamedAndTheConfigCannotBeUsedEither() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(Self.mine, local: "[general\n")
        let report = try await machine.runner().run(.setup(choices: SetupChoices(agents: ["claude", "codex"])))
        #expect(outcomes(report)["config"] == .failed && outcomes(report)["services"] == .skipped)
        let detail = try #require(report.step(.config)?.detail?.english())
        #expect(detail.contains(machine.paths.localConfigFile.path) && detail.contains("line 1"), "\(detail)")
        #expect(report.configEdits.isEmpty)
        #expect(report.needsUser.first?.text.contains("config.local.toml") == true)
        // The file that could be read says Ghostty and an agent, but it is not the whole config, so what the config asks for is not worked out from it.
        #expect(!report.needsUser.contains { $0.id == .automation }, "\(report.needsUser.map(\.id))")
    }

    @Test func startingTheConfigOverDoesNotMendAnOverlayThatDoesNotParse() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(Self.mine, local: "[general\n")
        let report = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "terminal"), force: true))
        #expect(outcomes(report)["config"] == .updated)
        // The step that cannot be done says so, since the config step did not.
        #expect(outcomes(report)["services"] == .failed && !report.ok)
        #expect(report.step(.services)?.detail?.english().contains(machine.paths.localConfigFile.path) == true)
        #expect(report.needsUser.first?.id == .config)
    }

    @Test func forceReplacesAConfigThatDoesNotParseAfterSavingIt() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(Self.broken)
        let report = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "terminal", editor: "zed", agents: []), force: true))
        #expect(report.ok && outcomes(report)["config"] == .updated && outcomes(report)["services"] == .created)
        let backups = try FileManager.default.contentsOfDirectory(atPath: machine.paths.configDirectory.path).filter { $0.hasPrefix("config.toml.bak-") }
        #expect(backups.count == 1)
        #expect(try String(contentsOf: machine.paths.configDirectory.appendingPathComponent(backups[0]), encoding: .utf8) == Self.broken)
        #expect(ConfigParser.parse(machine.configText).diagnostics.isEmpty)
    }

    @Test("a config that is there and cannot be read as one is a failure, whatever the reason", arguments: [
        ("a file that is not UTF-8", Data([0xff, 0xfe, 0x00, 0x41]), "not valid UTF-8"),
        ("a file past the size limit", Data(repeating: 0x23, count: ConfigParser.maxBytes + 100), "a config is a few kilobytes"),
    ])
    func aConfigThatCannotBeReadAsATextIsAFailure(_ what: String, _ bytes: Data, _ said: String) async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try writeBytes(bytes, to: machine.paths.configFile)
        let report = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "terminal")))
        #expect(outcomes(report)["config"] == .failed && outcomes(report)["services"] == .skipped, "\(what)")
        #expect(report.step(.config)?.detail?.english().contains(said) == true, "\(what): \(report.step(.config)?.detail?.english() ?? "")")
        #expect(report.configEdits.isEmpty)
        #expect(try Data(contentsOf: machine.paths.configFile) == bytes, "\(what): the file was changed")
    }

    @Test func aConfigThatCannotBeReadIsAFailureAndStaysAsItIs() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(Self.mine)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: machine.paths.configFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: machine.paths.configFile.path) }
        let report = try await machine.runner().run(.setup())
        #expect(outcomes(report)["config"] == .failed && !report.ok)
        #expect(report.step(.config)?.detail?.english().contains("cannot read") == true, "\(report.step(.config)?.detail?.english() ?? "")")
        #expect(outcomes(report)["services"] == .skipped)
    }

    @Test func aConfigThatIsALinkToNowhereIsAFailureThatNamesTheLinkAndMakesNothingThroughIt() async throws {
        // A dotfiles manager links the config to a repository that is not on this Mac yet.
        let machine = try Machine(); defer { machine.cleanUp() }
        let target = machine.home.appendingPathComponent("dotfiles/config.toml")
        try FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: machine.paths.configFile.path, withDestinationPath: target.path)
        let report = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "terminal", agents: [])))
        #expect(outcomes(report)["config"] == .failed && outcomes(report)["services"] == .skipped && !report.ok)
        let detail = try #require(report.step(.config)?.detail?.english())
        #expect(detail.contains("is a link to \(target.path), which does not exist"), "\(detail)")
        #expect(!FileManager.default.fileExists(atPath: target.path) && !FileManager.default.fileExists(atPath: target.deletingLastPathComponent().path), "something was made through the link")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: machine.paths.configFile.path)) == target.path, "the link was replaced")
        #expect(report.needsUser.first?.id == .config)
        // Starting over is the person's to ask for, and replaces the link.
        let forced = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "terminal", agents: []), force: true))
        #expect(forced.ok && ConfigParser.parse(machine.configText).config.terminal == "terminal")
    }

    @Test func aConfigThatAppearsWhileSetupMakesItsOwnIsKeptAndWhatTheChoicesNeedIsListed() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        // The login shell is asked before the config is written; another setup puts its own config there at that moment.
        let racing = ScriptedRunner { step in
            if step.executable == "/bin/zsh" {
                try? FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
                try? Self.mine.write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
            }
            return ProcessResult(status: 0, standardOutput: step.executable == "/bin/zsh" ? "claude\n" : "")
        }
        let runner = SetupRunner(facts: machine.facts, paths: machine.paths, runner: racing, rhPath: machine.rh, app: machine.app, trialHome: machine.home, localizer: .english, settle: .zero)
        let report = try await runner.run(.setup(choices: SetupChoices(terminal: "terminal")))
        #expect(outcomes(report)["config"] == .unchanged)
        #expect(report.step(.config)?.detail?.english().contains("made a moment ago by something else") == true)
        #expect(machine.configText == Self.mine)
        #expect(report.chosen == nil)
        // What the person chose is not in the config that stayed, so the report lists the edit instead of dropping the choice.
        #expect(report.configEdits.map(\.key) == ["general.terminal"], "\(report.configEdits.map(\.instruction))")
        #expect(report.warnings.contains { $0.contains("already exists, so Right Here left it alone") })
    }

    @Test func aConfigThatAppearsWhileSetupMakesItsOwnAndDoesNotParseIsAFailure() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let racing = ScriptedRunner { step in
            if step.executable == "/bin/zsh" {
                try? FileManager.default.createDirectory(at: machine.paths.configDirectory, withIntermediateDirectories: true)
                try? Self.broken.write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
            }
            return ProcessResult(status: 0, standardOutput: step.executable == "/bin/zsh" ? "claude\n" : "")
        }
        let runner = SetupRunner(facts: machine.facts, paths: machine.paths, runner: racing, rhPath: machine.rh, app: machine.app, trialHome: machine.home, localizer: .english, settle: .zero)
        let report = try await runner.run(.setup(choices: SetupChoices(terminal: "terminal")))
        #expect(outcomes(report)["config"] == .failed && outcomes(report)["services"] == .skipped && !report.ok)
        #expect(machine.configText == Self.broken)
    }

    // MARK: Dry run

    @Test func aDryRunWritesNothingAndStartsNothingThatChangesAnything() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let report = try await machine.runner(trial: false).run(.setup(choices: SetupChoices(terminal: "terminal"), dryRun: true))
        #expect(outcomes(report) == ["config": .created, "runnerScript": .created, "cliLink": .created, "services": .created, "finderExtension": .created])
        #expect(machine.mutations.isEmpty, "\(machine.mutations)")
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configDirectory.path))
        #expect(Installer(home: machine.home).installedServices().isEmpty)
        #expect(Installer(home: machine.home).existingCLILinkTarget() == nil)
        #expect(report.checks == nil && report.dryRun)
        #expect(report.chosen?.terminal?.id == "terminal")
        #expect(report.next == [SetupNext("rh setup --terminal terminal", why: "The same without --dry-run: it makes the changes above.")])
        #expect(report.english().first == "Right Here setup (a dry run: nothing was changed)")
        #expect(report.english().contains("  Config file: would be created (\(machine.paths.configFile.path))"))
    }

    @Test func aDryRunCountsTheQuickActionsOfTheConfigItWouldCreateNotOfNoConfigAtAll() async throws {
        // It said "5 installed" for a plan that the real run then made 7 of: the count came from the defaults that apply with no file.
        let machine = try Machine(shellOutput: "\nclaude\u{01}/usr/local/bin/claude\n\ncodex\u{01}/usr/local/bin/codex\n"); defer { machine.cleanUp() }
        let choices = SetupChoices(terminal: "ghostty", editor: "vscode", agents: ["claude", "codex"])
        func count(_ report: SetupReport) throws -> String {
            try #require(report.step(.services)?.detail?.english().split(separator: " ").first.map(String.init), "\(report.steps)")
        }
        let dry = try await machine.runner().run(.setup(choices: choices, dryRun: true))
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configFile.path))
        let real = try await machine.runner().run(.setup(choices: choices))
        #expect(try count(dry) == count(real), "dry run: \(dry.step(.services)?.detail?.english() ?? "-"); real run: \(real.step(.services)?.detail?.english() ?? "-")")
        #expect(dry.step(.services)?.detail?.english().hasSuffix(" in all") == true, "nothing is installed in a dry run, so it does not say \"installed\"")
        #expect(real.step(.services)?.detail?.english().hasSuffix(" installed") == true)
    }

    @Test func aDryRunAfterASetupFindsEverythingInPlace() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let runner = machine.runner(trial: false)
        _ = try await runner.run(.setup())
        let report = try await runner.run(.setup(dryRun: true))
        #expect(report.steps.allSatisfy { $0.outcome == .unchanged }, "\(report.steps.map { $0.english(dryRun: true) })")
    }

    // MARK: A step that cannot be done

    @Test func aRealFileInThePlaceOfTheLinkFailsThatStepAndTheRestIsDone() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let installer = Installer(home: machine.home)
        try FileManager.default.createDirectory(at: installer.locations.localBin, withIntermediateDirectories: true)
        try "#!/bin/sh\necho mine\n".write(to: installer.cliLink, atomically: true, encoding: .utf8)
        let report = try await machine.runner().run(.setup())
        #expect(!report.ok)
        #expect(outcomes(report)["cliLink"] == .failed)
        #expect(outcomes(report)["config"] == .created && outcomes(report)["services"] == .created && outcomes(report)["runnerScript"] == .created)
        #expect(try String(contentsOf: installer.cliLink, encoding: .utf8) == "#!/bin/sh\necho mine\n")
        let dry = try await machine.runner().run(.setup(dryRun: true))
        #expect(outcomes(dry)["cliLink"] == .failed, "a dry run has to tell what the real run cannot do")
    }

    @Test func anAppThatIsRunFromTheTemporaryLocationOfADownloadStopsBeforeAnythingIsWritten() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let translocated = "/private/var/folders/ab/cd/T/AppTranslocation/6F1B/d/Right Here.app/Contents/Helpers/rh"
        await #expect(throws: InstallError.translocated) { _ = try await machine.runner(rhPath: translocated).run(.setup()) }
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configDirectory.path))
    }

    // MARK: The Finder extension

    @Test func theExtensionIsRegisteredAndSwitchedOnFromTheAppThatHoldsThisRh() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let report = try await machine.runner(trial: false).run(.setup())
        #expect(outcomes(report)["finderExtension"] == .created)
        #expect(machine.mutations.contains("pluginkit -a \(machine.appex)"))
        #expect(machine.mutations.contains("pluginkit -e use -i \(AppIdentity.extensionBundleID)"))
        #expect(report.checks?.first { $0.id == .finderExtension }?.status == .ok)
        #expect(!report.needsUser.contains { $0.id == .finderExtension })
    }

    @Test func aCopyRegisteredFromAnotherPlaceIsRemovedFirst() async throws {
        let machine = try Machine(registered: ["/build/Right Here.app/Contents/PlugIns/FinderExtension.appex"], enabled: true); defer { machine.cleanUp() }
        let report = try await machine.runner(trial: false).run(.setup())
        #expect(outcomes(report)["finderExtension"] == .updated)
        let removed = try #require(machine.mutations.firstIndex(of: "pluginkit -r /build/Right Here.app/Contents/PlugIns/FinderExtension.appex"))
        let added = try #require(machine.mutations.firstIndex(of: "pluginkit -a \(machine.appex)"))
        #expect(removed < added, "the stale copy has to go before the new one is registered")
        #expect(machine.registered == [machine.appex])
        #expect(report.step(.finderExtension)?.detail?.english().contains("removed the stale registration of /build/") == true)
    }

    @Test func withNoAppTheExtensionIsSkippedForSetupAndAFailureWhenItWasAskedFor() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let runner = machine.runner(app: .some(nil), trial: false)
        let lenient = try await runner.run(.setup())
        #expect(lenient.step(.finderExtension)?.outcome == .skipped)
        #expect(lenient.step(.finderExtension)?.detail?.english() == "Right Here.app is not installed. Quick Actions work without it")
        #expect(lenient.ok)
        let strict = try await runner.run(SetupRequest(pieces: [.finderExtension], strict: true))
        #expect(strict.step(.finderExtension)?.outcome == .failed)
        #expect(!strict.ok)
    }

    @Test func anAppWithoutItsExtensionFailsThatStep() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try FileManager.default.removeItem(at: HostApp.extensionURL(in: machine.app))
        let report = try await machine.runner(trial: false).run(.setup())
        #expect(outcomes(report)["finderExtension"] == .failed)
        #expect(machine.mutations.allSatisfy { !$0.hasPrefix("pluginkit") })
    }

    @Test func aRegistrationThatIsOffIsTheOneThingLeftForThePerson() async throws {
        let machine = try Machine(registered: ["/x/FinderExtension.appex"], enabled: false); defer { machine.cleanUp() }
        // A machine where pluginkit keeps the switch off whatever it is told (the person has to flip it).
        let stubborn = ScriptedRunner { step in
            if step.executable == "/usr/bin/pluginkit", step.arguments.first == "-m" {
                return ProcessResult(status: 0, standardOutput: "-    \(AppIdentity.extensionBundleID)(1.0)\tU1\t2026-10-11 23:29:41 +0000\t\(machine.appex)\n")
            }
            return ProcessResult(status: 0, standardOutput: step.executable == "/bin/zsh" ? "claude\n" : "")
        }
        let runner = SetupRunner(facts: machine.facts, paths: machine.paths, runner: stubborn, rhPath: machine.rh, app: machine.app, trialHome: nil, localizer: .english, settle: .zero)
        let report = try await runner.run(.setup())
        let need = try #require(report.needsUser.first { $0.id == .finderExtension })
        #expect(need.text.contains("registered, but switched off"))
        #expect(need.how.joined().contains("General › Login Items & Extensions › Finder"))
        #expect(need.how.joined().contains("asks macOS to use it") && need.how.joined().contains("does not flip it"), "\(need.how)")
    }

    // MARK: Where rh runs from

    @Test func anRhThatRunsFromABuildFolderSaysThatTheRunnerScriptAndTheQuickActionsPointAtIt() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let build = "/work/right-here/.build/debug/rh"
        let report = try await machine.runner(trial: false, rhPath: build).run(.setup())
        let note = try #require(report.warnings.first { $0.contains("runs from a build folder") })
        #expect(note.contains(build) && note.contains("Right Here.app/Contents/Helpers/rh setup"), "\(note)")
        #expect(Installer(home: machine.home).installedRunnerTarget() == build)
        // The program inside the installed app, and a trial, say nothing of the kind.
        let installed = try await machine.runner(trial: false, rhPath: "/Applications/Right Here.app/Contents/Helpers/rh").run(.setup())
        #expect(!installed.warnings.contains { $0.contains("build folder") })
        let trial = try await machine.runner(trial: true, rhPath: build).run(.setup())
        #expect(!trial.warnings.contains { $0.contains("build folder") })
    }

    // MARK: One setup at a time

    @Test func aSetupWaitsForTheOneThatIsRunningAndMakesNothingUntilItIsDone() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let runner = machine.runner()
        // Another setup (the window, a terminal, an AI agent's) has its turn.
        let other = try FileLock.acquireNow(machine.paths.setupLockFile, timeout: .seconds(1))
        let waiting = Task { try await runner.run(.setup()) }
        try await Task.sleep(for: .milliseconds(600))
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configFile.path), "it did not wait for its turn")
        #expect(!FileManager.default.fileExists(atPath: Installer(home: machine.home).runnerScript.path))
        other.release()
        let report = try await waiting.value
        #expect(report.ok && outcomes(report)["config"] == .created)
    }

    @Test func twoSetupsAtOnceTakeTurnsAndTheSecondFindsEverythingInPlaceAndSaysSo() async throws {
        // They failed and left Quick Actions missing; the config was made by one and kept by the other. Now whichever comes second finds
        // every piece in place.
        for round in 0..<3 {
            let machine = try Machine(shellOutput: "\nclaude\u{01}/usr/local/bin/claude\n\ncodex\u{01}/usr/local/bin/codex\n"); defer { machine.cleanUp() }
            let runner = machine.runner()
            let choices = SetupChoices(terminal: "terminal", editor: "zed", agents: ["claude"])
            async let first = runner.run(.setup(choices: choices))
            async let second = runner.run(.setup(choices: choices))
            let reports = try await [first, second]
            #expect(reports.allSatisfy { $0.ok }, "round \(round)")
            let waited = try #require(reports.first { outcomes($0)["config"] == .unchanged }, "round \(round): both made the config")
            #expect(outcomes(waited) == ["config": .unchanged, "runnerScript": .unchanged, "cliLink": .unchanged, "services": .unchanged, "finderExtension": .skipped], "round \(round)")
            #expect(reports.filter { outcomes($0)["config"] == .created }.count == 1, "round \(round)")
            #expect(Installer(home: machine.home).installedServices().count == 6, "round \(round)")
        }
    }

    @Test func aSetupThatDoesNotGetItsTurnInTimeSaysSoAndWritesNothing() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let other = try FileLock.acquireNow(machine.paths.setupLockFile, timeout: .seconds(1))
        defer { other.release() }
        await #expect(throws: InstallError.anotherSetupIsRunning) { _ = try await machine.runner(lockTimeout: .milliseconds(300)).run(.setup()) }
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configFile.path))
        #expect(InstallError.anotherSetupIsRunning.errorDescription?.contains("run `rh setup` again") == true)
        // The window says it in the same words: it shows the error of a setup that did not start.
        let window = SetupActions(facts: machine.facts, paths: machine.paths, runner: machine.processRunner, helperPath: machine.rh, trialHome: machine.home, lockTimeout: .milliseconds(200))
        let result = await window.setUp()
        guard case .failed(let said)? = result.notice else { Issue.record("no failure was reported: \(String(describing: result.notice))"); return }
        #expect(said == InstallError.anotherSetupIsRunning.errorDescription && result.report == nil)
    }

    @Test func aSetupSaysEachPhaseBeforeItStartsAndThatItWaitsWhenAnotherHoldsTheTurn() async throws {
        // The window shows the phase while it runs: a run takes seconds, and a button that only greys out for that long looked stuck.
        let machine = try Machine(); defer { machine.cleanUp() }
        let said = Mutex<[SetupPhase]>([])
        _ = try await machine.runner().run(.repair(), progress: { phase in said.withLock { $0.append(phase) } })
        #expect(said.withLock { $0 } == SetupPiece.allCases.map(SetupPhase.piece) + [.checkup])

        said.withLock { $0 = [] }
        let other = try FileLock.acquireNow(machine.paths.setupLockFile, timeout: .seconds(1))
        await #expect(throws: InstallError.anotherSetupIsRunning) {
            _ = try await machine.runner(lockTimeout: .milliseconds(200)).run(.repair(), progress: { phase in said.withLock { $0.append(phase) } })
        }
        other.release()
        #expect(said.withLock { $0 } == [.waiting], "a setup that waits for its turn says so, and starts nothing else")
    }

    @Test func anRhInAnOlderCopyOfTheAppSetsNothingUpAndNamesTheNewerOne() async throws {
        // An AI agent that runs `rh setup` through an old copy's rh would point every click at that copy.
        let machine = try Machine(); defer { machine.cleanUp() }
        let old = machine.home.path + "/Applications/Right Here.app/Contents/Helpers/rh"
        var facts = machine.facts
        facts.copies[AppIdentity.hostBundleID] = [AppCopy(path: "/Applications/Right Here.app", version: "99.0"), AppCopy(path: machine.home.path + "/Applications/Right Here.app", version: AppIdentity.version)]
        let runner = SetupRunner(facts: facts, paths: machine.paths, runner: machine.processRunner, rhPath: old, app: nil, trialHome: machine.home, settle: .zero)
        let refused = InstallError.notTheCopyToKeep(copy: machine.home.path + "/Applications/Right Here.app", version: AppIdentity.version, keep: "/Applications/Right Here.app", keepVersion: "99.0")
        await #expect(throws: refused) { _ = try await runner.run(.setup()) }
        // The command it names is one to paste: "Right Here.app" has a space.
        #expect(refused.errorDescription?.hasSuffix("Run the other copy's rh: '/Applications/Right Here.app/Contents/Helpers/rh' setup") == true, "\(refused.errorDescription ?? "")")
        #expect(InstallError.problem(runningFrom: "/Users/x/.Trash/Right Here.app/Contents/Helpers/rh") == .inTrash)
        #expect(!FileManager.default.fileExists(atPath: machine.paths.configFile.path))
        // The newest copy, and an rh outside an app (a build folder, Homebrew's), set up as before.
        #expect(InstallError.problem(helper: "/Applications/Right Here.app/Contents/Helpers/rh", version: "99.0", copies: facts.copies[AppIdentity.hostBundleID] ?? [], home: machine.home.path) == nil)
        #expect(InstallError.problem(helper: "/opt/homebrew/bin/rh", version: "0.1", copies: facts.copies[AppIdentity.hostBundleID] ?? [], home: machine.home.path) == nil)
    }

    @Test func eachPhaseHasALineForTheCommandLineInEnglish() {
        #expect(SetupPhase.piece(.finderExtension).englishLine == "Registering the Finder extension. This takes a few seconds…")
        #expect(SetupPhase.waiting.englishLine == "Waiting for another setup to finish…")
        #expect(([.waiting, .checkup] + SetupPiece.allCases.map(SetupPhase.piece)).allSatisfy { !$0.englishLine.isEmpty && !$0.englishLine.contains(".setup") })
    }

    @Test func onlyTheWindowsSetupAsksTheLoginShellAboutEveryAgent() async throws {
        // `rh setup` has no use for the agents that are not in the menu, and with none in it, it starts no shell for them.
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nagents = [\"claude\"]\n")
        let command = try await machine.runner().run(.repair())
        #expect(command.shell?.asked == ["claude"], "\(command.shell?.asked ?? [])")
        let window = await SetupActions(facts: machine.facts, paths: machine.paths, runner: machine.processRunner, helperPath: machine.rh, trialHome: machine.home).repair()
        #expect(window.report?.shell?.asked.contains("gemini") == true)
    }

    @Test func rewritingTheQuickActionsAfterAChangeDoesNotWaitForAnotherSetup() async throws {
        // The window's change holds the window while it runs: waiting for `rh setup` in a terminal would hold it for up to two minutes, and that setup writes them itself.
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nagents = [\"claude\"]\n")
        let other = try FileLock.acquireNow(machine.paths.setupLockFile, timeout: .seconds(1))
        defer { other.release() }
        let actions = SetupActions(facts: machine.facts, paths: machine.paths, runner: machine.processRunner, helperPath: machine.rh, trialHome: machine.home, lockTimeout: .seconds(30))
        let started = ContinuousClock.now
        let result = await actions.updateQuickActions()
        #expect(ContinuousClock.now - started < .seconds(5) && result.notice != nil)
    }

    @Test func aDryRunNeitherWaitsForAnotherSetupNorMakesTheLockFile() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let report = try await machine.runner(lockTimeout: .milliseconds(100)).run(.setup(dryRun: true))
        #expect(report.ok && !FileManager.default.fileExists(atPath: machine.paths.configDirectory.path), "a dry run writes nothing")
        let other = try FileLock.acquireNow(machine.paths.setupLockFile, timeout: .seconds(1))
        defer { other.release() }
        let again = try await machine.runner(lockTimeout: .milliseconds(100)).run(.setup(dryRun: true))
        #expect(again.ok, "a dry run waited for a setup that is running")
    }

    // MARK: What is left for the person

    @Test func theLinkNeedsThePathLineUnlessTheTerminalAlreadyHasIt() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let report = try await machine.runner(trial: false).run(.setup())
        let need = try #require(report.needsUser.first { $0.id == .path })
        #expect(need.how.contains { $0.contains("~/.zshrc") && $0.contains("export PATH=\"$HOME/.local/bin:$PATH\"") }, "\(need.how)")
        #expect(need.how.last == "Right Here does not edit your shell's startup files.")
    }

    @Test func aTrialSaysNothingAboutTheExtensionButWhatARealRunSaysAboutThePathAndThePermission() async throws {
        // An AI agent that tries setup in a trial (`RH_HOME`) must meet the list the person will: the doctor warns about the PATH, so
        // the list says the same, with the line to add.
        let machine = try Machine(); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup())
        #expect(report.checks?.contains { $0.id == .finderExtension } == false, "a trial neither registers nor checks the extension")
        var facts = machine.facts
        facts.copies[AppIdentity.hostBundleID] = [AppCopy(path: "/Applications/Right Here.app", version: "1.0"), AppCopy(path: "/Applications/Old/Right Here.app", version: "0.1")]
        let withCopies = try await SetupRunner(facts: facts, paths: machine.paths, runner: machine.processRunner, rhPath: machine.rh, app: nil, trialHome: machine.home, settle: .zero).run(.setup())
        #expect(withCopies.checks?.contains { $0.id == .appCopies } == false, "the copies of the app are this Mac's, not the trial's")
        #expect(report.needsUser.map(\.id) == [.path, .automation], "\(report.needsUser.map(\.id))")
        let path = try #require(report.needsUser.first { $0.id == .path })
        #expect(path.how.contains { $0.contains("export PATH=\"$HOME/.local/bin:$PATH\"") }, "\(path.how)")
        #expect(report.next.contains { $0.command == "rh doctor --probe-launch" })
    }

    @Test func startingAnAgentInGhosttyHasMacOSAskForPermissionOnce() async throws {
        let machine = try Machine(shellOutput: "\nclaude\u{01}/usr/local/bin/claude\n"); defer { machine.cleanUp() }
        let report = try await machine.runner(trial: false).run(.setup())
        let need = try #require(report.needsUser.first { $0.id == .automation })
        #expect(need.text == "The first time Right Here starts an agent in ⟦user⟧Ghostty⟦/user⟧, macOS asks whether Right Here may control ⟦user⟧Ghostty⟦/user⟧. Click Allow.")
        #expect(report.next.contains { $0.command == "rh doctor --probe-launch" })
    }

    @Test func withoutAnAgentNothingStartsAndNothingNeedsPermission() async throws {
        let machine = try Machine(shellOutput: ""); defer { machine.cleanUp() }
        let report = try await machine.runner(trial: false).run(.setup(choices: SetupChoices(agents: [])))
        #expect(!report.needsUser.contains { $0.id == .automation })
        #expect(!report.next.contains { $0.command.contains("probe") })
    }

    // MARK: The report as data and as text

    @Test func theReportIsJSONThatAProgramCanRead() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup())
        let data = try JSONEncoder().encode(report)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["ok"] as? Bool == true)
        #expect(json["dryRun"] as? Bool == false)
        #expect(json["trialHome"] as? String == machine.home.path)
        let steps = try #require(json["steps"] as? [[String: Any]])
        #expect(steps.map { $0["id"] as? String } == ["config", "runnerScript", "cliLink", "services", "finderExtension"])
        #expect(steps.first?["outcome"] as? String == "created")
        #expect((steps.first?["text"] as? String)?.hasPrefix("Config file: created (") == true)
        for key in ["configEdits", "warnings", "needsUser", "next", "checks", "chosen"] { #expect(json[key] != nil, "\(key) is missing") }
        let checks = try #require(json["checks"] as? [[String: Any]])
        #expect(checks.first?["id"] as? String == "config")
    }

    @Test func aDryRunSaysInItsJSONWhatWouldBeDoneAndNeverThatItWasDone() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let installer = Installer(home: machine.home)
        try FileManager.default.createDirectory(at: installer.locations.localBin, withIntermediateDirectories: true)
        try "#!/bin/sh\necho mine\n".write(to: installer.cliLink, atomically: true, encoding: .utf8)
        let report = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "terminal"), dryRun: true))
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        #expect(json["dryRun"] as? Bool == true && json["ok"] as? Bool == false)
        let steps = try #require(json["steps"] as? [[String: Any]])
        let words = Dictionary(uniqueKeysWithValues: steps.map { ($0["id"] as? String ?? "", $0["outcome"] as? String ?? "") })
        #expect(words == ["config": "would-create", "runnerScript": "would-create", "cliLink": "would-fail", "services": "would-create", "finderExtension": "skipped"], "\(words)")
        for step in steps {
            let text = step["text"] as? String ?? ""
            let word = step["outcome"] as? String ?? ""
            #expect(word.hasPrefix("would-") ? text.contains("would") : !text.contains("would"), "\(word): \(text)")
            #expect(!text.contains(": created") && !text.contains(": updated") && !text.contains(": failed"), "a dry run says it did something: \(text)")
        }
        // The same steps of a real run keep the words of what was done.
        let real = try await machine.runner().run(.setup())
        let realWords = try #require((try JSONSerialization.jsonObject(with: JSONEncoder().encode(real)) as? [String: Any])?["steps"] as? [[String: Any]]).map { $0["outcome"] as? String ?? "" }
        #expect(realWords == ["created", "created", "failed", "created", "skipped"], "\(realWords)")
    }

    @Test func onlyWhatWouldChangeSomethingOrFailGetsAWouldInTheDryRun() {
        for outcome in [SetupStep.Outcome.created, .updated, .unchanged, .skipped, .failed] {
            let changes = [SetupStep.Outcome.created, .updated, .failed].contains(outcome)
            #expect(outcome.word(dryRun: false) == outcome.rawValue)
            #expect(outcome.word(dryRun: true).hasPrefix("would-") == changes, "\(outcome)")
        }
    }

    @Test func theSetupWindowHasSomethingToSayOfAReportWhenAChoiceCouldNotBeAppliedOrThereIsAWarningOrAStepFailed() async throws {
        // A first run that went well is one calm line. The window shows the list of what setup did only when there is more than that: an
        // agent that ran `rh setup` while the chooser was open made the config, so the picks were left out, and nothing in the window said so.
        let calm = try Machine(); defer { calm.cleanUp() }
        let first = try await calm.runner(trial: false).run(.setup())
        #expect(first.ok && first.warnings.isEmpty && first.configEdits.isEmpty && !first.hasNews)

        let kept = try Machine(); defer { kept.cleanUp() }
        try kept.writeConfig(Self.mine)
        let notApplied = try await kept.runner(trial: false).run(.setup(choices: SetupChoices(agents: ["claude", "codex"])))
        #expect(notApplied.ok && !notApplied.configEdits.isEmpty && notApplied.hasNews)
        #expect(notApplied.english().contains(SetupReport.editsHeading), "the window and the text say the same before the edits")

        let warned = try Machine(); defer { warned.cleanUp() }
        let warp = try await warned.runner(trial: false).run(.setup(choices: SetupChoices(terminal: "warp", agents: ["claude"])))
        #expect(warp.ok && !warp.warnings.isEmpty && warp.hasNews)

        let broken = try Machine(); defer { broken.cleanUp() }
        try broken.writeConfig(Self.broken)
        let failed = try await broken.runner(trial: false).run(.setup())
        #expect(!failed.ok && failed.hasNews)
    }

    @Test func theTextNamesWhatWasDoneWhatWasChosenAndWhatToRunNext() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let lines = try await machine.runner(trial: false).run(.setup()).english()
        #expect(lines.first == "Right Here setup")
        #expect(lines.contains { $0.hasPrefix("  Config file: created (") })
        #expect(lines.contains("  terminal: Ghostty (ghostty, found on this Mac)"))
        #expect(lines.contains { $0.hasPrefix("  agents: ") && $0.contains("found in your login shell") })
        #expect(lines.contains("Only you can do this:"))
        #expect(lines.contains("  rh menu --container ~"))
    }

    @Test func whatTheConfigWouldAskForIsNotDerivedFromAConfigThatCannotBeUsed() {
        let config = ConfigParser.parse("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n").config
        let facts = FakeSystemFacts(homeDirectory: URL(fileURLWithPath: "/Users/tester"), applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app")])
        #expect(SetupAdvice.needsUser(checks: [], config: config, facts: facts).map(\.id) == [.automation])
        #expect(SetupAdvice.needsUser(checks: [], config: nil, facts: facts).isEmpty)
    }

    @Test func eachShellGetsTheLineItReads() {
        let home = URL(fileURLWithPath: "/Users/tester/.local/bin")
        #expect(SetupAdvice.pathNeed(localBin: home, loginShell: "/bin/zsh").how.first?.hasPrefix("Add this line to ~/.zshrc:") == true)
        #expect(SetupAdvice.pathNeed(localBin: home, loginShell: "/bin/bash").how.first?.hasPrefix("Add this line to ~/.bash_profile:") == true)
        #expect(SetupAdvice.pathNeed(localBin: home, loginShell: "/opt/homebrew/bin/fish").how.first == "Run this once in a fish prompt: fish_add_path $HOME/.local/bin")
    }
}
