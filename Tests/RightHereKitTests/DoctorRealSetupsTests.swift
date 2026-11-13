import Foundation
import Testing
@testable import RightHereCore
@testable import RightHereKit

// What `rh doctor` says on real setups, from an independent review (2026-11-13): each test describes a setup the doctor once got wrong.
// Everything is written under a temporary home; no live process is asked, except a POSIX login shell with an empty home of its own.

/// A throwaway home with a config folder in it.
private struct RealSetupHome {
    let home: URL
    let paths: RHPaths

    init() throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }

    func write(_ text: String, to file: URL, executable: Bool = false) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
    }

    func writeConfig(_ text: String) throws { try write(text, to: paths.configFile) }

    func link(_ link: URL, to target: String) throws {
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target)
    }

    /// The runner script `rh setup` writes, starting `target`.
    func installRunner(pointingAt target: String) throws {
        try write(Installer.runnerScriptText(rhPath: target), to: Installer(home: home).runnerScript, executable: true)
    }
}

/// Starts the real login shell with an empty home of the test's (no startup file of the person's runs); pluginkit gets a canned answer.
private struct RealSetupLoginShell: ProcessRunner {
    let home: URL
    let pluginkit: ProcessResult

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        if step.executable == "/usr/bin/pluginkit" { return pluginkit }
        var step = step
        step.environment.merge(["HOME": home.path, "ZDOTDIR": home.path, "XDG_CONFIG_HOME": home.appendingPathComponent(".config").path, "ENV": "", "BASH_ENV": ""]) { $1 }
        return try await LiveProcessRunner().run(step, timeout: timeout)
    }
}

private let realSetupPluginkitEnabled = "+    \(AppIdentity.extensionBundleID)(1.0)\tU1\t2026-10-11 23:29:41 +0000\t/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex\n"
private let realSetupGhostty: [String: URL] = ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app")]
private let realSetupGhosttyVersion = ["com.mitchellh.ghostty": "1.3.1"]

/// What the doctor prints for a row, for the failure message.
private func realSetupSaid(_ check: DoctorCheck?) -> String {
    check.map { $0.englishLines().joined(separator: " / ") } ?? "(no row)"
}

@Suite("rh doctor on real setups")
struct DoctorRealSetupsTests {
    // MARK: rh on the PATH

    /// Homebrew installs: the cask's `binary` stanza and the formula both put `rh` in Homebrew's bin, which `brew shellenv` puts on the PATH; a default
    /// macOS PATH has no ~/.local/bin. `rh setup` still makes ~/.local/bin/rh, and the row then says `rh` is not on the PATH.
    @Test func rhThatHomebrewPutOnThePathIsNotCalledUnreachable() async throws {
        let scene = try RealSetupHome(); defer { scene.cleanUp() }
        let brewBin = scene.home.appendingPathComponent("opt/homebrew/bin")
        let brewRH = brewBin.appendingPathComponent("rh")
        try scene.write("#!/bin/sh\n", to: brewRH, executable: true)
        try scene.link(Installer(home: scene.home).cliLink, to: brewRH.path)
        // The window and an AI agent's process have launchd's PATH; the login shell has Homebrew's bin and an `rh` in it.
        let facts = FakeSystemFacts(homeDirectory: scene.home, variables: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        let shell = "\nrh\u{01}\(brewRH.path)\n\u{01}rh-path\u{01}\(brewBin.path):/usr/bin:/bin:/usr/sbin:/sbin\n\(Detector.doneMarker)\n"
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: shell), ProcessResult(status: 0, standardOutput: realSetupPluginkitEnabled)])
        let checks = await Doctor(facts: facts, paths: scene.paths, loaded: ConfigStore.load(paths: scene.paths), runner: runner, rhPath: brewRH.path).run()
        let link = checks.first { $0.id == .cliLink }
        #expect(link?.status == .ok, "doctor: \(realSetupSaid(link))")
        let path = SetupAdvice.needsUser(checks: checks, config: nil, facts: facts).filter { $0.id == .path }
        #expect(path.isEmpty, "rh setup tells the person: \(path.map(\.text))")
    }

    /// The app was moved (from ~/Applications to /Applications) after `rh setup` linked `rh` into it: typing `rh` starts nothing.
    @Test func aCommandLinkToNothingIsNotOk() async throws {
        let scene = try RealSetupHome(); defer { scene.cleanUp() }
        let installer = Installer(home: scene.home)
        let gone = scene.home.appendingPathComponent("Applications/Right Here.app/Contents/Helpers/rh").path
        try scene.link(installer.cliLink, to: gone)
        try scene.installRunner(pointingAt: gone)
        let facts = FakeSystemFacts(homeDirectory: scene.home, variables: ["PATH": "\(installer.locations.localBin.path):/usr/bin:/bin"])
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: realSetupPluginkitEnabled)])
        let checks = await Doctor(facts: facts, paths: scene.paths, loaded: ConfigStore.load(paths: scene.paths), runner: runner, rhPath: "/Applications/Right Here.app/Contents/Helpers/rh").run()
        let runnerRow = checks.first { $0.id == .finderRunner }
        let link = checks.first { $0.id == .cliLink }
        #expect(!FileManager.default.isExecutableFile(atPath: installer.cliLink.path), "sanity: the link leads nowhere")
        #expect(runnerRow?.status == .fail, "sanity, the runner row in the same run: \(realSetupSaid(runnerRow))")
        #expect(link?.status != .ok, "doctor: \(realSetupSaid(link))")
    }

    // MARK: Quick Actions

    /// The window's Quick Actions page can take the last one out, which writes `items = []`; the person chose to have none.
    @Test func noQuickActionsBecauseTheConfigListsNoneIsNotAWarning() throws {
        let scene = try RealSetupHome(); defer { scene.cleanUp() }
        try scene.writeConfig("[services]\nitems = []\n")
        let loaded = ConfigStore.load(paths: scene.paths)
        let facts = FakeSystemFacts(homeDirectory: scene.home)
        #expect(loaded.config.serviceItems == [] && loaded.result.diagnostics.isEmpty, "sanity: the config takes an empty list without a word")
        let specs = ActionRegistry(config: loaded.config, facts: facts).serviceSpecs(rhPath: "/opt/rh/bin/rh")
        // What `rh setup` sees: nothing to install, so its step says "unchanged", and the row would stay as it is.
        #expect(specs.isEmpty && Installer(home: scene.home).servicesAreCurrent(specs), "sanity: setup has nothing to do")
        let check = Doctor(facts: facts, paths: scene.paths, loaded: loaded, runner: FakeProcessRunner(), rhPath: "/opt/rh/bin/rh").servicesCheck()
        #expect(check.status == .ok, "doctor: \(realSetupSaid(check))")
    }

    /// The catalog offers the repository links as Quick Actions (the window lists them); `gitCheck` reads only the menu.
    @Test func aRepositoryQuickActionOnAMacWithoutGitIsNotSilent() throws {
        let scene = try RealSetupHome(); defer { scene.cleanUp() }
        try scene.writeConfig("[services]\nitems = [\"copy-path.absolute\", \"repository.copy-link\"]\n")
        let loaded = ConfigStore.load(paths: scene.paths)
        let facts = FakeSystemFacts(homeDirectory: scene.home)
        #expect(ActionRegistry(config: loaded.config, facts: facts).serviceSpecs(rhPath: "/opt/rh/bin/rh").contains { $0.actionID == "repository.copy-link" },
                "sanity: rh setup installs the Quick Action")
        let check = Doctor(facts: facts, paths: scene.paths, loaded: loaded, runner: FakeProcessRunner(), rhPath: "/opt/rh/bin/rh", gitInstalled: false).gitCheck()
        #expect(check?.status == .warn, "doctor: \(realSetupSaid(check))")
    }

    /// `launcher = "desktop"` opens the agent's desktop app through its deep link and types nothing, so the command does not have to be on the PATH. The menu has
    /// no More Agent Options (whose start options are always typed into a terminal): every Claude entry of the menu and of the Quick Actions opens the app.
    @Test func anAgentStartedThroughItsDesktopAppDoesNotNeedItsCommand() async throws {
        let scene = try RealSetupHome(); defer { scene.cleanUp() }
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n\n[agent.claude]\nlauncher = \"desktop\"\n\n[menu]\nitems = [\"open-terminal\", \"agents\", \"copy-path\"]\n")
        let loaded = ConfigStore.load(paths: scene.paths)
        let facts = FakeSystemFacts(homeDirectory: scene.home, applications: realSetupGhostty.merging(["com.anthropic.claudefordesktop": URL(fileURLWithPath: "/Applications/Claude.app")]) { $1 },
                                    bundleVersions: realSetupGhosttyVersion)
        let agent = try #require(loaded.config.agent(id: "claude"))
        let menu = MenuBuilder(config: loaded.config, facts: facts).build(for: HereContext(origin: .container, container: scene.home)).flatMap(\.actionIDs)
        let quickActions = ActionRegistry(config: loaded.config, facts: facts).serviceSpecs(rhPath: "/opt/rh/bin/rh").map(\.actionID)
        let entries = (menu + quickActions).filter { $0.hasPrefix("agent.claude") || $0.hasPrefix("preset.") }
        let typed = entries.filter { id in
            guard case .agent(_, let variant, let launcher)? = ActionRef(parsing: id) else { return true }
            if case .success(.desktop(_)) = AgentLaunchResolution.resolve(agent: agent, hasVariant: variant != nil, explicit: launcher, config: loaded.config, facts: facts).route { return false }
            return true
        }
        #expect(!entries.isEmpty && typed.isEmpty, "sanity: every Claude entry opens the desktop app: \(entries), typed: \(typed)")
        // The login shell got to its end and does not know `claude`: no Claude Code command-line tool, only the desktop app.
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "\n\(Detector.doneMarker)\n"), ProcessResult(status: 0, standardOutput: realSetupPluginkitEnabled)])
        let checks = await Doctor(facts: facts, paths: scene.paths, loaded: loaded, runner: runner, rhPath: "/opt/rh/bin/rh").run()
        let row = checks.first { $0.id == .agent("claude") }
        // Not found is true, and said; taking the agent out of general.agents would take out the entry that works.
        #expect(row?.fix?.key != .doctorFixAgentRemove, "doctor: \(realSetupSaid(row))")
    }

    /// `[agent.claude] terminal = "iterm"` on a Mac without iTerm: the agent's own terminal decides, and general.terminal does not.
    @Test func anAgentsOwnTerminalThatIsMissingIsNotFixedThroughGeneralTerminal() async throws {
        let scene = try RealSetupHome(); defer { scene.cleanUp() }
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n\n[agent.claude]\nterminal = \"iterm\"\n")
        let loaded = ConfigStore.load(paths: scene.paths)
        let facts = FakeSystemFacts(homeDirectory: scene.home, applications: realSetupGhostty.merging(["com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")]) { $1 },
                                    bundleVersions: realSetupGhosttyVersion)
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "\nclaude\u{01}/usr/local/bin/claude\n\(Detector.doneMarker)\n"),
                                                 ProcessResult(status: 0, standardOutput: realSetupPluginkitEnabled)])
        let checks = await Doctor(facts: facts, paths: scene.paths, loaded: loaded, runner: runner, rhPath: "/opt/rh/bin/rh").run()
        let row = checks.first { $0.id == .agent("claude") }
        // Doing what the fix says: another general.terminal, which is installed, leaves the agent as it was.
        var followed = loaded.config
        followed.terminal = "terminal"
        #expect(!ActionRegistry(config: followed, facts: facts).info(.agent(id: "claude", variant: nil, launcher: nil)).available, "sanity: changing general.terminal does not help")
        #expect(row?.status == .warn && row?.fix?.english().contains("general.terminal") != true, "doctor: \(realSetupSaid(row))")
    }

    /// Codex with `launcher = "desktop"` and no Codex app: the fix offers another general.terminal (not used), "link" (Codex has none) or "desktop" (what fails now).
    @Test func anAgentWhoseDesktopAppIsMissingIsNotToldToSetTheLauncherItHas() async throws {
        let scene = try RealSetupHome(); defer { scene.cleanUp() }
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"codex\"]\n\n[agent.codex]\nlauncher = \"desktop\"\n")
        let loaded = ConfigStore.load(paths: scene.paths)
        let facts = FakeSystemFacts(homeDirectory: scene.home, applications: realSetupGhostty.merging(["com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")]) { $1 },
                                    bundleVersions: realSetupGhosttyVersion)
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "\ncodex\u{01}/usr/local/bin/codex\n\(Detector.doneMarker)\n"),
                                                 ProcessResult(status: 0, standardOutput: realSetupPluginkitEnabled)])
        let checks = await Doctor(facts: facts, paths: scene.paths, loaded: loaded, runner: runner, rhPath: "/opt/rh/bin/rh").run()
        let row = checks.first { $0.id == .agent("codex") }
        let codex = ActionRef.agent(id: "codex", variant: nil, launcher: nil)
        var otherTerminal = loaded.config
        otherTerminal.terminal = "terminal"
        var link = loaded.config
        link.agents["codex"]?.launcher = .terminalLink
        #expect(!ActionRegistry(config: otherTerminal, facts: facts).info(codex).available && !ActionRegistry(config: link, facts: facts).info(codex).available,
                "sanity: neither another general.terminal nor launcher = \"link\" starts it")
        #expect(row?.status == .warn && row?.fix?.english().contains("\"desktop\"") != true && row?.fix?.english().contains("general.terminal") != true, "doctor: \(realSetupSaid(row))")
    }

    /// `command = "~/.claude/local/claude"`: the line a click types gets tilde expansion, the lookup of `"$n"` does not. Measured with the real /bin/sh and an empty home.
    @Test func anAgentCommandWithATildeIsFoundTheWayTheTypedLineFindsIt() async throws {
        let scene = try RealSetupHome(); defer { scene.cleanUp() }
        try scene.write("#!/bin/sh\necho ran-claude\n", to: scene.home.appendingPathComponent(".claude/local/claude"), executable: true)
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n\n[agent.claude]\ncommand = \"~/.claude/local/claude\"\n")
        let loaded = ConfigStore.load(paths: scene.paths)
        #expect(loaded.result.diagnostics.isEmpty, "sanity: the config takes the command: \(loaded.result.diagnostics.map { $0.summary(file: loaded.file) })")
        let facts = FakeSystemFacts(homeDirectory: scene.home, loginShell: "/bin/sh", applications: realSetupGhostty, bundleVersions: realSetupGhosttyVersion)
        let runner = RealSetupLoginShell(home: scene.home, pluginkit: ProcessResult(status: 0, standardOutput: realSetupPluginkitEnabled))
        let agent = try #require(loaded.config.agent(id: "claude"))
        let line = try AgentLaunchResolution.typedLine(agent: agent, variant: nil, options: loaded.config.launchOptions(for: agent)).get()
        let typed = try await runner.run(ProcessStep(executable: "/bin/sh", arguments: ["-lic", line]), timeout: .seconds(10))
        #expect(typed.standardOutput.contains("ran-claude"), "sanity: the typed line `\(line)` runs the program in the login shell: \(typed.standardError)")
        let checks = await Doctor(facts: facts, paths: scene.paths, loaded: loaded, runner: runner, rhPath: "/opt/rh/bin/rh").run()
        let row = checks.first { $0.id == .agent("claude") }
        #expect(row?.status == .ok, "doctor: \(realSetupSaid(row))")
    }

    /// A typo while editing (the Config page can now edit the text): the file is not TOML any more, and the rows below the config row are worked out from the defaults.
    @Test func aConfigThatCannotBeReadIsNotAdvisedOnAsIfItWereTheDefaults() async throws {
        let scene = try RealSetupHome(); defer { scene.cleanUp() }
        let good = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"
        let facts = FakeSystemFacts(homeDirectory: scene.home, applications: realSetupGhostty, bundleVersions: realSetupGhosttyVersion)
        try scene.writeConfig(good)
        // The Quick Actions that `rh setup` made from the good file.
        _ = try Installer(home: scene.home).installServices(ActionRegistry(config: ConfigStore.load(paths: scene.paths).config, facts: facts).serviceSpecs(rhPath: "/opt/rh/bin/rh"))
        try scene.writeConfig(good + "\n[menu\n")
        let loaded = ConfigStore.load(paths: scene.paths)
        #expect(ConfigProblem(loaded.result, paths: scene.paths) != nil, "sanity: setup uses nothing from this file and skips the Quick Actions")
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: realSetupPluginkitEnabled)])
        let checks = await Doctor(facts: facts, paths: scene.paths, loaded: loaded, runner: runner, rhPath: "/opt/rh/bin/rh").run()
        let agents = checks.first { $0.id == .agents }
        let services = checks.first { $0.id == .services }
        #expect(agents?.fix?.key != .doctorFixAgentsAdd, "doctor: \(realSetupSaid(agents)); the file already says agents = [\"claude\"]")
        #expect(services?.fix != .doctorFixRunSetup, "doctor: \(realSetupSaid(services)); rh setup skips the Quick Actions while the file cannot be used")
    }

    /// The older copy, opened by Spotlight from another Applications folder: its doctor calls the runner script, which runs the copy to keep, stale, and says
    /// to run `rh setup`, which this copy refuses to do. The Quick Actions row of the same run counts the other copy's `rh` as current.
    @Test func theOlderCopysDoctorDoesNotAskForASetupThatItRefuses() async throws {
        let scene = try RealSetupHome(); defer { scene.cleanUp() }
        let newer = scene.home.appendingPathComponent("Applications/Right Here.app")
        let older = scene.home.appendingPathComponent("Applications/Old/Right Here.app")
        let newerRH = newer.appendingPathComponent("Contents/Helpers/rh").path
        let olderRH = older.appendingPathComponent("Contents/Helpers/rh").path
        try scene.write("#!/bin/sh\n", to: URL(fileURLWithPath: newerRH), executable: true)
        try scene.write("#!/bin/sh\n", to: URL(fileURLWithPath: olderRH), executable: true)
        try scene.installRunner(pointingAt: newerRH)
        let copies = [AppCopy(path: newer.path, version: "1.2.25"), AppCopy(path: older.path, version: "1.2.0")]
        var facts = FakeSystemFacts(homeDirectory: scene.home)
        facts.copies[AppIdentity.hostBundleID] = copies
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: realSetupPluginkitEnabled)])
        let checks = await Doctor(facts: facts, paths: scene.paths, loaded: ConfigStore.load(paths: scene.paths), runner: runner, rhPath: olderRH).run()
        let row = checks.first { $0.id == .finderRunner }
        let refused = InstallError.problem(helper: olderRH, version: "1.2.0", copies: copies, home: scene.home.path)
        #expect(refused != nil, "sanity: rh setup from this copy stops")
        #expect(!(row?.fix == .doctorFixRunSetup && refused != nil), "doctor: \(realSetupSaid(row)); rh setup from this copy: \(refused?.errorDescription ?? "-")")
    }

    // MARK: Last action

    /// After the log passed 1 MB it was moved to rh.log.1; the newest action is the newest line of rh.log.
    @Test func theNewestActionIsTakenFromTheCurrentLogAndNotTheRotatedOne() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rh.log")
        try "2026-10-12T05:50:00Z ok agent.codex [container, 0 items]\n".write(to: file, atomically: true, encoding: .utf8)
        try "2026-10-11T12:00:00Z ok new-file.md [toolbar, 0 items]\n".write(to: file.appendingPathExtension("1"), atomically: true, encoding: .utf8)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-12T06:00:00Z"))
        let check = Doctor.activityCheck(logFile: file, now: now)
        #expect(check.detail?.english().contains("agent.codex") == true, "doctor: \(realSetupSaid(check))")
    }
}
