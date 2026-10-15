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

    private struct State {
        var registered: [String] = []
        var enabled = false
        var steps: [ProcessStep] = []
    }

    private let state = Mutex(State())

    init(shellOutput: String = "claude\ncodex\n", registered: [String] = [], enabled: Bool = false) throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
        self.shellOutput = shellOutput
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
            return ProcessResult(status: 0, standardOutput: shellOutput + (wantsPath ? "\u{01}rh-path\u{01}/usr/bin:/bin\n" : ""))
        default:
            return ProcessResult(status: 0)
        }
    }

    func runner(app: URL?? = nil, trial: Bool = true, rhPath: String? = nil) -> SetupRunner {
        SetupRunner(facts: facts, paths: paths, runner: processRunner, rhPath: rhPath ?? rh, app: app ?? self.app,
                    trialHome: trial ? home : nil, localizer: .english, settle: .zero)
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

    @Test func theConfigIsMadeFromWhatIsInstalledAndTheSetupSaysWhatItFound() async throws {
        let machine = try Machine(shellOutput: "claude\ncodex\n"); defer { machine.cleanUp() }
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
        let machine = try Machine(shellOutput: "claude\n"); defer { machine.cleanUp() }
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
        let machine = try Machine(shellOutput: "claude\ncodex\n"); defer { machine.cleanUp() }
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
        let machine = try Machine(shellOutput: "codex\n"); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup(choices: SetupChoices(editor: "zed")))
        let chosen = try #require(report.chosen)
        #expect(chosen.terminal?.id == "ghostty" && chosen.terminal?.source == .found)
        #expect(chosen.editor?.id == "zed" && chosen.editor?.source == .you)
        #expect(chosen.agents.map(\.id) == ["codex"])
    }

    @Test func noAgentsIsAChoiceToo() async throws {
        let machine = try Machine(shellOutput: "claude\ncodex\n"); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup(choices: SetupChoices(agents: [])))
        #expect(report.chosen?.agents.isEmpty == true)
        #expect(ConfigParser.parse(machine.configText).config.enabledAgents.isEmpty)
    }

    @Test func anInstalledTerminalThatCannotRunCommandsGetsAWarningWhenAgentsAreChosen() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup(choices: SetupChoices(terminal: "alacritty", agents: ["claude"])))
        #expect(report.warnings.contains { $0.contains("Alacritty cannot run commands") }, "\(report.warnings)")
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
        #expect(report.english().contains { $0.contains("In config.toml on line 7, change agents = [\"claude\"] to agents = [\"claude\", \"codex\"].") })
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

    @Test func aConfigThatCannotBeReadIsKeptAndSaidSo() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig(Self.mine)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: machine.paths.configFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: machine.paths.configFile.path) }
        let report = try await machine.runner().run(.setup())
        #expect(outcomes(report)["config"] == .unchanged)
        #expect(report.step(.config)?.detail?.english().contains("was not read") == true, "\(report.step(.config)?.detail?.english() ?? "")")
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
        #expect(need.how.joined().contains("does not switch it on"))
    }

    // MARK: What is left for the person

    @Test func theLinkNeedsThePathLineUnlessTheTerminalAlreadyHasIt() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let report = try await machine.runner(trial: false).run(.setup())
        let need = try #require(report.needsUser.first { $0.id == .path })
        #expect(need.how.contains { $0.contains("~/.zshrc") && $0.contains("export PATH=\"$HOME/.local/bin:$PATH\"") }, "\(need.how)")
        #expect(need.how.last == "Right Here does not edit your shell's startup files.")
    }

    @Test func aTrialSaysNothingAboutTheExtensionTheMacOrThePath() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let report = try await machine.runner().run(.setup())
        #expect(report.needsUser.isEmpty)
        #expect(report.checks?.contains { $0.id == .finderExtension } == false)
    }

    @Test func startingAnAgentInGhosttyHasMacOSAskForPermissionOnce() async throws {
        let machine = try Machine(shellOutput: "claude\n"); defer { machine.cleanUp() }
        let report = try await machine.runner(trial: false).run(.setup())
        let need = try #require(report.needsUser.first { $0.id == .automation })
        #expect(need.text == "The first time Right Here starts an agent in Ghostty, macOS asks whether Right Here may control Ghostty. Click Allow.")
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

    @Test func eachShellGetsTheLineItReads() {
        let home = URL(fileURLWithPath: "/Users/tester/.local/bin")
        #expect(SetupAdvice.pathNeed(localBin: home, loginShell: "/bin/zsh").how.first?.hasPrefix("Add this line to ~/.zshrc:") == true)
        #expect(SetupAdvice.pathNeed(localBin: home, loginShell: "/bin/bash").how.first?.hasPrefix("Add this line to ~/.bash_profile:") == true)
        #expect(SetupAdvice.pathNeed(localBin: home, loginShell: "/opt/homebrew/bin/fish").how.first == "Run this once in a fish prompt: fish_add_path $HOME/.local/bin")
    }
}
