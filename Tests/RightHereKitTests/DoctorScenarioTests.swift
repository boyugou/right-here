import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

/// A throwaway home with a config folder in it, plus the system facts and tool answers one doctor run needs. Nothing
/// outside the home is touched and no process is started.
private struct Scene {
    let home: URL
    let paths: RHPaths
    var applications: [String: URL] = [:]
    var bundleVersions: [String: String] = [:]
    var files: Set<String> = []
    var variables: [String: String] = [:]
    /// What the tools answer, in the order the doctor asks: the login shell (looking for agent commands, only when
    /// some agent is enabled), then pluginkit.
    var answers: [ProcessResult] = []
    var rhPath: String? = "/opt/rh/bin/rh"

    init() throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }

    func writeConfig(_ text: String, to file: URL? = nil) throws {
        let file = file ?? paths.configFile
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// A runner script that starts `target`, which exists and can be run when `exists` is true.
    func installRunner(pointingAt target: String, exists: Bool) throws {
        let installer = Installer(home: home)
        try FileManager.default.createDirectory(at: installer.locations.applicationScripts, withIntermediateDirectories: true)
        try Installer.runnerScriptText(rhPath: target).write(to: installer.runnerScript, atomically: true, encoding: .utf8)
        if exists {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: target).deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\n".write(toFile: target, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target)
        }
    }

    func linkCLI(to target: String) throws {
        let installer = Installer(home: home)
        try FileManager.default.createDirectory(at: installer.locations.localBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: installer.cliLink.path, withDestinationPath: target)
    }

    func run(with runner: FakeProcessRunner? = nil) async -> [DoctorCheck] {
        let facts = FakeSystemFacts(homeDirectory: home, files: files, applications: applications, bundleVersions: bundleVersions, variables: variables)
        let doctor = Doctor(facts: facts, paths: paths, loaded: ConfigStore.load(paths: paths), runner: runner ?? FakeProcessRunner(results: answers), rhPath: rhPath)
        return await doctor.run()
    }
}

/// What a check says, in English.
private struct Said: Equatable, CustomStringConvertible {
    var status: DoctorCheck.Status
    var detail: String?
    var fix: String?
    var notes: [String] = []
    var description: String { "\(status.rawValue) | \(detail ?? "-") | \(notes) | \(fix ?? "-")" }
}

private func said(_ check: DoctorCheck?) -> Said? {
    check.map { Said(status: $0.status, detail: $0.detail?.english(), fix: $0.fix?.english(), notes: $0.notes.map { $0.english() }) }
}

private func said(_ checks: [DoctorCheck], _ id: String) -> Said? {
    said(checks.first { $0.id.rawValue == id })
}

private let ghostty = URL(fileURLWithPath: "/Applications/Ghostty.app")
private let vscode = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
private let pluginkitEnabled = "+    \(AppIdentity.extensionBundleID)(1.0)\tU1\t2026-10-11 23:29:41 +0000\t/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex\n"

@Suite("Doctor: what each state of the machine says")
struct DoctorScenarioTests {
    @Test func anEmptyMachineSaysWhatIsMissingAndWhatToRun() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0)]
        let checks = await scene.run()
        #expect(checks.map(\.id.rawValue) == ["config", "terminal.default", "editor.default", "agents", "finder.runner", "services", "cli.link", "finder.extension", "finder.activity"])
        #expect(said(checks, "config") == Said(status: .warn, detail: "none at \(scene.paths.configFile.path); defaults apply", fix: "Run `rh setup`."))
        #expect(said(checks, "terminal.default") == Said(status: .fail, detail: "No terminal is installed.", fix: "Install a terminal or set general.terminal."))
        #expect(said(checks, "editor.default") == Said(status: .warn, detail: "No editor is installed.", fix: "Install an editor or set general.editor."))
        #expect(said(checks, "agents") == Said(status: .warn, detail: "none enabled", fix: "Add agents to general.agents, for example agents = [\"claude\"]."))
        #expect(said(checks, "finder.runner") == Said(status: .fail, detail: "not installed; the Finder menu cannot run actions", fix: "Run `rh setup`."))
        #expect(said(checks, "services") == Said(status: .warn, detail: "none installed; Quick Actions and keyboard shortcuts are not available", fix: "Run `rh setup`."))
        #expect(said(checks, "cli.link") == Said(status: .warn, detail: "no link at \(scene.home.path)/.local/bin/rh", fix: "Run `rh setup`."))
        #expect(said(checks, "finder.extension") == Said(status: .fail, detail: "not registered; Finder shows no Right Here menu", fix: "Install Right Here.app, then run `rh setup`."))
        #expect(said(checks, "finder.activity") == Said(status: .ok, detail: "none yet; right-click a folder in Finder and choose an action, then run `rh doctor` again", fix: nil))
    }

    @Test func theClaudeCodeLinkHandlerIsCheckedOnlyWhereSomethingStartsClaudeCodeThroughIt() async throws {
        // All three agents of the cold-agent evaluation told their person about this warning, one of them a person who had said that
        // they use no agent and one whose own menu has no entry that uses the link: a handler nothing needs is nobody's business.
        func claudeLink(_ config: String, shell: String = "claude\n") async throws -> Said? {
            var scene = try Scene(); defer { scene.cleanUp() }
            scene.applications = ["com.mitchellh.ghostty": ghostty]
            scene.answers = [ProcessResult(status: 0, standardOutput: shell), ProcessResult(status: 0, standardOutput: pluginkitEnabled)]
            try scene.writeConfig(config)
            return said(await scene.run(), "claude.link")
        }
        let general = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"
        let ownMenu = "[menu]\nitems = [\"open-terminal\", \"agents\"]\n"

        // The default menu has the entry (More Agent Options), so the warning stays.
        #expect(try await claudeLink(general) == Said(status: .warn, detail: "handler not installed (only needed for launcher = \"link\")",
                                                      fix: "Start `claude` once and send a prompt; Claude Code registers the handler."))
        // Where nothing uses the link there is no row: no Claude Code, none at all, or a menu of the person's own.
        for agents in ["[\"codex\"]", "[]"] {
            #expect(try await claudeLink("[general]\nterminal = \"ghostty\"\nagents = \(agents)\n", shell: "codex\n") == nil, "agents = \(agents)")
        }
        #expect(try await claudeLink(general + ownMenu) == nil, "a menu without More Agent Options never offers the link")
        // Each way of reaching the link brings the row back.
        #expect(try await claudeLink(general + ownMenu + "[agent.claude]\nlauncher = \"link\"\n")?.status == .warn, "the agent starts through the link")
        #expect(try await claudeLink(general + ownMenu + "[services]\nitems = [\"agent.claude@link\"]\n")?.status == .warn, "a Quick Action uses the link")
        #expect(try await claudeLink(general + "[menu]\nitems = [\"agents-more\"]\n")?.status == .warn, "the menu has More Agent Options")
    }

    @Test func aWorkingMachineIsAllOkAndNamesWhatItFound() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.applications = ["com.mitchellh.ghostty": ghostty, "com.microsoft.VSCode": vscode]
        scene.bundleVersions = ["com.mitchellh.ghostty": "1.3.1"]
        scene.files = [scene.home.appendingPathComponent("Applications/Claude Code URL Handler.app").path]
        scene.variables = ["PATH": "\(scene.home.path)/.local/bin:/usr/bin"]
        scene.answers = [ProcessResult(status: 0, standardOutput: "\nclaude\u{01}/usr/local/bin/claude\n"), ProcessResult(status: 0, standardOutput: pluginkitEnabled)]
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = [\"claude\"]\n")
        let target = scene.home.appendingPathComponent("bin/rh").path
        scene.rhPath = target
        try scene.installRunner(pointingAt: target, exists: true)
        try scene.linkCLI(to: target)
        let checks = await scene.run()
        #expect(said(checks, "config") == Said(status: .ok, detail: scene.paths.configFile.path, fix: nil))
        #expect(said(checks, "terminal.default") == Said(status: .ok, detail: "Open in Ghostty", fix: nil))
        #expect(said(checks, "editor.default") == Said(status: .ok, detail: "Open in Visual Studio Code", fix: nil))
        #expect(said(checks, "agent.claude") == Said(status: .ok, detail: "`claude` found; starts with Claude Code Here", fix: nil))
        #expect(said(checks, "claude.link") == Said(status: .ok, detail: "handler installed", fix: nil))
        #expect(said(checks, "finder.runner") == Said(status: .ok, detail: "runs \(target)", fix: nil))
        #expect(said(checks, "cli.link") == Said(status: .ok, detail: "\(scene.home.path)/.local/bin/rh", fix: nil))
        // Not just the path: an ok row says the extension is switched on, which is what lets the menu appear.
        #expect(said(checks, "finder.extension") == Said(status: .ok, detail: "switched on: /Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex", fix: nil))
    }

    @Test func anAgentThatStartsWithItsPermissionPromptsOffSaysSoInItsRow() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.applications = ["com.mitchellh.ghostty": ghostty]
        scene.bundleVersions = ["com.mitchellh.ghostty": "1.3.1"]
        scene.answers = [ProcessResult(status: 0, standardOutput: "\nclaude\u{01}/usr/local/bin/claude\n\ncodex\u{01}/usr/local/bin/codex\n"), ProcessResult(status: 0, standardOutput: pluginkitEnabled)]
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\", \"codex\"]\n[agent.claude]\nbypass_permissions = true\n")
        let checks = await scene.run()
        // A choice the person made is not a warning, but the row never stays silent about it; the other agent's row is as before.
        #expect(said(checks, "agent.claude") == Said(status: .ok, detail: "`claude` found; starts with Claude Code Here and its permission prompts switched off (`--dangerously-skip-permissions`)", fix: nil))
        #expect(said(checks, "agent.codex") == Said(status: .ok, detail: "`codex` found; starts with Codex Here", fix: nil))
    }

    @Test func anAgentWhoseOwnCommandTypesTheFlagSaysSoInItsRowToo() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.applications = ["com.mitchellh.ghostty": ghostty]
        scene.bundleVersions = ["com.mitchellh.ghostty": "1.3.1"]
        scene.answers = [ProcessResult(status: 0, standardOutput: "\nclaude\u{01}/usr/local/bin/claude\n\ncodex\u{01}/usr/local/bin/codex\n"), ProcessResult(status: 0, standardOutput: pluginkitEnabled)]
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n[agent.claude]\ncommand = \"claude --dangerously-skip-permissions\"\n")
        let checks = await scene.run()
        #expect(said(checks, "agent.claude")?.detail?.contains("permission prompts switched off (`--dangerously-skip-permissions`)") == true, "\(String(describing: said(checks, "agent.claude")))")
    }

    @Test func anAgentThatTheLoginShellDoesNotFindSaysSoAndHowToRemoveIt() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.applications = ["com.mitchellh.ghostty": ghostty]
        scene.bundleVersions = ["com.mitchellh.ghostty": "1.3.1"]
        // The shell got to the end of its script (the last line) and did not name the command: it is not there.
        scene.answers = [ProcessResult(status: 0, standardOutput: "\u{01}rh-done\u{01}\n"), ProcessResult(status: 0)]
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        let checks = await scene.run()
        #expect(said(checks, "agent.claude") == Said(status: .warn, detail: "`claude` is not found in your login shell", fix: "Install it, or remove \"claude\" from general.agents."))
        #expect(checks.first { $0.id == .agent("claude") }?.title == "Claude Code")
    }

    @Test func anAgentWhenTheLoginShellSaidNothingIsUnknownAndNotMissing() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.applications = ["com.mitchellh.ghostty": ghostty]
        scene.bundleVersions = ["com.mitchellh.ghostty": "1.3.1"]
        // A startup file that exits (an `exec tmux`, a prompt that waits) leaves no last line: nobody knows whether the command is there, so the row does not say it is not,
        // and does not tell the person to remove it.
        scene.answers = [ProcessResult(status: 1), ProcessResult(status: 0)]
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        let checks = await scene.run()
        #expect(said(checks, "agent.claude") == Said(status: .warn, detail: "`claude`: your login shell did not say whether it is installed", fix: nil))
    }

    @Test func anAgentThatTheShellNamedBeforeItWasStoppedIsStillFound() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.applications = ["com.mitchellh.ghostty": ghostty]
        scene.bundleVersions = ["com.mitchellh.ghostty": "1.3.1"]
        // What it printed before it stopped is evidence for the commands it names, and for none of the others.
        scene.answers = [ProcessResult(status: 1, standardOutput: "\nclaude\u{01}/usr/local/bin/claude\n"), ProcessResult(status: 0)]
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\", \"codex\"]\n")
        let checks = await scene.run()
        #expect(said(checks, "agent.claude")?.status == .ok)
        #expect(said(checks, "agent.codex")?.detail == "`codex`: your login shell did not say whether it is installed")
    }

    @Test func anAgentThatCannotStartSaysWhyAndOffersOtherLaunchers() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0, standardOutput: "\nclaude\u{01}/usr/local/bin/claude\n"), ProcessResult(status: 0)]
        try scene.writeConfig("[general]\nagents = [\"claude\"]\n")
        let agent = said(await scene.run(), "agent.claude")
        #expect(agent?.status == .warn)
        #expect(agent?.detail == "No terminal is installed.")
        #expect(agent?.fix == "Choose another terminal with general.terminal, or set launcher = \"link\" or \"desktop\".")
    }

    /// The row of an agent whose terminal only opens folders is the catalog's sentence, which the window writes in the person's language;
    /// it was the planner's English refusal in every language.
    @Test func anAgentInATerminalThatOnlyOpensFoldersSaysSoInTheCatalogsWords() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.applications = ["dev.warp.Warp-Stable": URL(fileURLWithPath: "/Applications/Warp.app")]
        scene.answers = [ProcessResult(status: 0, standardOutput: "\nclaude\u{01}/usr/local/bin/claude\n\u{01}rh-done\u{01}\n"), ProcessResult(status: 0)]
        try scene.writeConfig("[general]\nterminal = \"warp\"\nagents = [\"claude\"]\n")
        let checks = await scene.run()
        #expect(checks.first { $0.id == .agent("claude") }?.detail == .appTerminalNoAgents("Warp"))
        #expect(said(checks, "agent.claude")?.status == .warn)
    }

    @Test func aDefaultAppThatIsNotInstalledSaysSoAndWhichOne() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0)]
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\n")
        let checks = await scene.run()
        #expect(said(checks, "terminal.default") == Said(status: .fail, detail: "Ghostty is not installed.", fix: "Install a terminal or set general.terminal."))
        #expect(said(checks, "editor.default") == Said(status: .warn, detail: "Visual Studio Code is not installed.", fix: "Install an editor or set general.editor."))
        // These are the catalog's sentences, which the setup window writes in the system language.
        #expect(checks.first { $0.id == .terminalDefault }?.detail == .doctorAppNotInstalled("Ghostty"))
        #expect(checks.first { $0.id == .editorDefault }?.detail == .doctorAppNotInstalled("Visual Studio Code"))
    }

    @Test func aDefaultAppTheConfigGetsWrongFallsBackToTheFirstInstalledOne() async throws {
        // An unknown terminal and a terminal named as the editor are errors of the config check, and the setting is
        // dropped: the rows say what is used instead, never an unknown app.
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0)]
        scene.applications = ["com.mitchellh.ghostty": ghostty, "com.microsoft.VSCode": vscode]
        try scene.writeConfig("[general]\nterminal = \"ghosty\"\neditor = \"ghostty\"\n")
        let checks = await scene.run()
        #expect(said(checks, "config")?.status == .fail)
        #expect(said(checks, "terminal.default") == Said(status: .ok, detail: "Open in Ghostty", fix: nil))
        #expect(said(checks, "editor.default") == Said(status: .ok, detail: "Open in Visual Studio Code", fix: nil))
    }

    @Test func aDefaultAppThatIsNotInstalledWhileAnotherIsSaysWhichOneIsUsedInstead() async throws {
        // A config shared between Macs: it names iTerm and Zed, this Mac has Ghostty and Visual Studio Code. The menu works, so it is
        // a warning, and it names both.
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0)]
        scene.applications = ["com.mitchellh.ghostty": ghostty, "com.microsoft.VSCode": vscode]
        try scene.writeConfig("[general]\nterminal = \"iterm\"\neditor = \"zed\"\n")
        let checks = await scene.run()
        #expect(said(checks, "terminal.default") == Said(status: .warn, detail: "iTerm is not installed; Ghostty is used instead.",
                                                         fix: "Install it, or change general.terminal (remove the setting to use the first installed terminal)."))
        #expect(said(checks, "editor.default") == Said(status: .warn, detail: "Zed is not installed; Visual Studio Code is used instead.",
                                                       fix: "Install it, or change general.editor (remove the setting to use the first installed editor)."))
        #expect(checks.first { $0.id == .terminalDefault }?.detail == .doctorAppFallback("iTerm", "Ghostty"))
    }

    @Test func aConfigThatLeavesTheMenuEmptyForAFolderSaysWhyAndHowToSeeEveryEntry() async throws {
        // Nothing in the file is wrong, and the Finder menu does not appear: `agents = []` with a menu of groups, no copy-path style.
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0)]
        try scene.writeConfig("[general]\nagents = []\n[copy_path]\nstyles = []\n[menu]\nitems = [\"agents\", \"presets\", \"agents-more\", \"copy-path\"]\n")
        let checks = await scene.run()
        let menu = try #require(checks.first { $0.id == .finderMenu })
        #expect(menu.status == .warn && menu.title == "Finder menu")
        #expect(menu.detail?.english() == "empty for a folder: no entry is left with this config")
        #expect(menu.notes.map { $0.english() } == ["Agents: none is enabled; general.agents lists none.", "Copy Path: copy_path.styles lists no style."])
        #expect(menu.fix?.english() == "Run `rh menu --explain` to see why each entry is left out.")
        // Where the config is fine the row is not there at all: a healthy setup stays quiet.
        var quiet = try Scene(); defer { quiet.cleanUp() }
        quiet.answers = [ProcessResult(status: 0)]
        try quiet.writeConfig("[general]\nterminal = \"ghostty\"\n")
        #expect(!(await quiet.run()).contains { $0.id == .finderMenu })
    }

    @Test("the runner script says whether it runs this rh", arguments: [
        (true, "/opt/other/bin/rh", DoctorCheck.Status.warn, "points at {target}, not at this rh"),
        (false, "/opt/rh/bin/rh", .fail, "points at {target}, which does not exist")
    ])
    func theRunnerScript(exists: Bool, thisRH: String, status: DoctorCheck.Status, detail: String) async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0)]
        scene.rhPath = thisRH
        let target = scene.home.appendingPathComponent("elsewhere/rh").path
        try scene.installRunner(pointingAt: target, exists: exists)
        let runner = said(await scene.run(), "finder.runner")
        #expect(runner == Said(status: status, detail: detail.replacingOccurrences(of: "{target}", with: target), fix: "Run `rh setup`."))
    }

    @Test func theCommandLinkSaysWhenItsFolderIsNotOnThePath() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0, standardOutput: "\u{01}rh-path\u{01}/usr/bin\n")]
        scene.variables = ["PATH": "/usr/bin"]
        try scene.linkCLI(to: "/opt/rh/bin/rh")
        let link = said(await scene.run(), "cli.link")
        #expect(link == Said(status: .warn, detail: "linked at \(scene.home.path)/.local/bin/rh, but that folder is not on PATH", fix: "Add ~/.local/bin to PATH in your shell profile."))
    }

    @Test("a login shell that gives no PATH leaves it unknown: the row is ok and nobody is told to edit a profile", arguments: [
        ProcessResult(status: 0),                                        // the startup file exited, or printed nothing we asked for
        ProcessResult(status: 15, terminatedAfter: .seconds(10)),        // the startup file took longer than the probe waits
        ProcessResult(status: 0, standardOutput: "welcome back\n")        // only what the startup files said
    ])
    func anUnansweredShellIsNotAWrongPath(answer: ProcessResult) async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [answer]
        scene.variables = ["PATH": "/usr/bin"]
        try scene.linkCLI(to: "/opt/rh/bin/rh")
        let link = said(await scene.run(), "cli.link")
        #expect(link == Said(status: .ok, detail: "linked at \(scene.home.path)/.local/bin/rh; your login shell did not say whether that folder is on PATH", fix: nil))
    }

    @Test("the folder is on the PATH however its entry is spelled", arguments: [
        "{home}/.local/bin/", "{home}/.local//bin", "{home}/./.local/bin", "{home}/.local/../.local/bin", "{home}/.local/bin/."
    ])
    func spellingsOfTheSameFolder(entry: String) async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.variables = ["PATH": "/usr/bin:" + entry.replacingOccurrences(of: "{home}", with: scene.home.path)]
        try scene.linkCLI(to: "/opt/rh/bin/rh")
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: pluginkitEnabled)])
        let checks = await scene.run(with: runner)
        #expect(said(checks, "cli.link")?.status == .ok)
        #expect(runner.recorded.map(\.executable) == ["/usr/bin/pluginkit"], "the shell was asked although this process's PATH has the folder")
    }

    @Test func aFolderThatIsOnlyReachedThroughASymbolicLinkIsTheSameFolder() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        let real = scene.home.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: scene.home.appendingPathComponent(".local"), withDestinationURL: real)
        scene.variables = ["PATH": "/usr/bin:" + real.appendingPathComponent("bin").path]
        try scene.linkCLI(to: "/opt/rh/bin/rh")
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: pluginkitEnabled)])
        let link = said(await scene.run(with: runner), "cli.link")
        #expect(link == Said(status: .ok, detail: "\(scene.home.path)/.local/bin/rh", fix: nil), "the row said: \(String(describing: link))")
        #expect(runner.recorded.map(\.executable) == ["/usr/bin/pluginkit"], "the shell was asked although this process's PATH has the folder")
    }

    @Test("an entry that is not an absolute folder, or another folder, is not the link's folder", arguments: [
        "bin", "", ".", "~/.local/bin", "/usr/local/bin", "{home}/.local/bin2", "{home}/.local"
    ])
    func notTheSameFolder(entry: String) {
        let home = URL(fileURLWithPath: "/Users/tester")
        let folder = home.appendingPathComponent(".local/bin")
        #expect(!Doctor.pathListsFolder([entry.replacingOccurrences(of: "{home}", with: home.path)], folder))
        #expect(Doctor.pathListsFolder(["/usr/bin", entry.replacingOccurrences(of: "{home}", with: home.path), "/Users/tester/.local/bin"], folder))
    }

    /// What the login shell prints for its `PATH`: the line a probe asks for, after whatever the startup files said.
    private func shellPath(_ folders: [String], noise: String = "") -> ProcessResult {
        ProcessResult(status: 0, standardOutput: noise + "\u{01}rh-path\u{01}" + folders.joined(separator: ":") + "\n")
    }

    @Test func aLinkInAFolderThatOnlyTheLoginShellsPathHasIsOnThePath() async throws {
        // A window of the app, or a program an AI assistant started, has launchd's PATH; the person's terminal has their own.
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.variables = ["PATH": "/usr/bin:/bin"]
        try scene.linkCLI(to: "/opt/rh/bin/rh")
        scene.answers = [shellPath(["/opt/homebrew/bin", "\(scene.home.path)/.local/bin", "/usr/bin"], noise: "welcome back\n")]
        let link = said(await scene.run(), "cli.link")
        #expect(link == Said(status: .ok, detail: "\(scene.home.path)/.local/bin/rh", fix: nil))
    }

    @Test func aLinkInAFolderNeitherPathHasIsNotOnThePath() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.variables = ["PATH": "/usr/bin:/bin"]
        try scene.linkCLI(to: "/opt/rh/bin/rh")
        scene.answers = [shellPath(["/opt/homebrew/bin", "/usr/bin"])]
        let link = said(await scene.run(), "cli.link")
        #expect(link?.status == .warn)
        #expect(link?.detail == "linked at \(scene.home.path)/.local/bin/rh, but that folder is not on PATH")
    }

    @Test func thisProcessesOwnPathIsEnoughAndNoShellIsStartedForIt() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.variables = ["PATH": "\(scene.home.path)/.local/bin:/usr/bin"]
        try scene.linkCLI(to: "/opt/rh/bin/rh")
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: pluginkitEnabled)])
        let checks = await scene.run(with: runner)
        #expect(said(checks, "cli.link")?.status == .ok)
        #expect(runner.recorded.map(\.executable) == ["/usr/bin/pluginkit"], "the login shell was started: \(runner.recorded.map(\.executable))")
    }

    @Test func withoutALinkTheShellIsNotAskedForAPath() async throws {
        let scene = try Scene(); defer { scene.cleanUp() }
        let runner = FakeProcessRunner()
        _ = await scene.run(with: runner)
        #expect(runner.recorded.map(\.executable) == ["/usr/bin/pluginkit"], "\(runner.recorded.map(\.executable))")
    }

    @Test func theAgentCommandsAndThePathComeFromOneStartOfTheLoginShell() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.applications = ["com.mitchellh.ghostty": ghostty]
        scene.variables = ["PATH": "/usr/bin"]
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        try scene.linkCLI(to: "/opt/rh/bin/rh")
        let runner = FakeProcessRunner(results: [
            ProcessResult(status: 0, standardOutput: "\nclaude\u{01}/usr/local/bin/claude\n\u{01}rh-path\u{01}/usr/bin:\(scene.home.path)/.local/bin\n"),
            ProcessResult(status: 0, standardOutput: pluginkitEnabled)])
        let checks = await scene.run(with: runner)
        #expect(said(checks, "agent.claude")?.status == .ok)
        #expect(said(checks, "cli.link")?.status == .ok)
        #expect(runner.recorded.count == 2, "\(runner.recorded.map(\.executable))")
    }

    @Test func severalInstalledCopiesOfTheAppAreAWarningThatNamesThemAndOneIsNoRow() async throws {
        let scene = try Scene(); defer { scene.cleanUp() }
        var facts = FakeSystemFacts(homeDirectory: scene.home)
        let doctor = { (facts: FakeSystemFacts) in Doctor(facts: facts, paths: scene.paths, loaded: ConfigStore.load(paths: scene.paths), runner: FakeProcessRunner(), rhPath: scene.rhPath) }
        facts.copies[AppIdentity.hostBundleID] = [AppCopy(path: "/Applications/Right Here.app", version: "0.3.7")]
        #expect(doctor(facts).copiesCheck() == nil)
        facts.copies[AppIdentity.hostBundleID] = [AppCopy(path: scene.home.path + "/Applications/Right Here.app", version: "0.3.2"), AppCopy(path: "/Applications/Right Here.app", version: "0.3.7"),
                                                  AppCopy(path: "/Volumes/Right Here/Right Here.app", version: "0.3.6")]
        let check = try #require(doctor(facts).copiesCheck())
        #expect(said(check) == Said(status: .warn, detail: "2 copies are installed: 0.3.7 (/Applications), 0.3.2 (~/Applications)",
                                    fix: "Keep /Applications/Right Here.app and move the other copies to the Trash. Spotlight and Launchpad can open any of them."))
    }

    @Test func whatACheckNamesInsideItsSentenceIsInItsLanguage() async throws {
        // "starts with Claude Code Here" stayed English in a German window, and the command line's English sentences must not turn German.
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.applications = ["com.mitchellh.ghostty": ghostty]
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        func examined(_ language: String) async -> [DoctorCheck] {
            let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "\nclaude\u{01}/opt/claude\n\u{01}rh-done\u{01}\n"), ProcessResult(status: 0, standardOutput: pluginkitEnabled)])
            let facts = FakeSystemFacts(homeDirectory: scene.home, applications: scene.applications)
            return await Doctor(facts: facts, paths: scene.paths, loaded: ConfigStore.load(paths: scene.paths), runner: runner, rhPath: scene.rhPath).examine(language: language).checks
        }
        let german = Localizer(languages: ["de"])
        let agent = await examined("de").first { $0.id == .agent("claude") }?.detail
        #expect(agent.map { german.render($0) }?.contains(german.render(.menuAgentHere("Claude Code"))) == true, "\(agent.map { german.render($0) } ?? "")")
        let english = await examined("en").first { $0.id == .agent("claude") }?.detail?.english()
        #expect(english?.contains("Claude Code Here") == true, "\(english ?? "")")
    }

    @Test func theQuickActionsAreExpectedInTheLanguageTheConfigNames() async throws {
        // Their names are translated: setup writes them in the config's language, and the check must expect the same names, or it would say they differ for ever.
        let scene = try Scene(); defer { scene.cleanUp() }
        try scene.writeConfig("[general]\nlanguage = \"de\"\nagents = []\n\n[services]\nitems = [\"copy-path.absolute\"]\n")
        let facts = FakeSystemFacts(homeDirectory: scene.home)
        let loaded = ConfigStore.load(paths: scene.paths)
        let specs = ActionRegistry(config: loaded.config, facts: facts, localizer: Localizer(languages: ["de"])).serviceSpecs(rhPath: "/opt/rh/bin/rh")
        #expect(try #require(specs.first).title != ActionRegistry(config: loaded.config, facts: facts, localizer: .english).serviceSpecs(rhPath: "/opt/rh/bin/rh").first?.title)
        _ = try Installer(home: scene.home).installServices(specs)
        let check = Doctor(facts: facts, paths: scene.paths, loaded: loaded, runner: FakeProcessRunner(), rhPath: scene.rhPath).servicesCheck()
        #expect(check.status == .ok, "\(check.detail?.english() ?? "")")
    }

    @Test func theWindowsDoctorAsksTheSameStartOfTheShellAboutEveryAgentAndSaysWhereEachIs() async throws {
        // The Agents page says, for each agent the config knows, whether a terminal would find it; the checks stay about the enabled ones.
        let scene = try Scene(); defer { scene.cleanUp() }
        try scene.writeConfig("[general]\nagents = [\"claude\"]\n")
        let runner = FakeProcessRunner(results: [
            ProcessResult(status: 0, standardOutput: "\nclaude\u{01}/opt/claude\n\ngemini\u{01}/opt/gemini\n\(Detector.doneMarker)\n"),
            ProcessResult(status: 0, standardOutput: pluginkitEnabled)])
        let facts = FakeSystemFacts(homeDirectory: scene.home)
        let examined = await Doctor(facts: facts, paths: scene.paths, loaded: ConfigStore.load(paths: scene.paths), runner: runner, rhPath: scene.rhPath).examine(everyAgent: true)
        let asked = try #require(runner.recorded.first).arguments
        #expect(asked.contains("claude") && asked.contains("gemini") && asked.contains("codex"), "\(asked)")
        #expect(examined.shell.locations == ["claude": "/opt/claude", "gemini": "/opt/gemini"] && examined.shell.answered)
        #expect(examined.checks.contains { $0.id == .agent("claude") } && !examined.checks.contains { $0.id == .agent("gemini") }, "a row for an agent that is not enabled")
        #expect(runner.recorded.count == 2, "the shell was started more than once: \(runner.recorded.map(\.executable))")
    }

    @Test func aFinderExtensionThatIsSwitchedOffIsForThePersonToFix() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0, standardOutput: pluginkitEnabled.replacingOccurrences(of: "+    ", with: "-    "))]
        let extensionCheck = said(await scene.run(), "finder.extension")
        #expect(extensionCheck == Said(status: .needsUser, detail: "registered but switched off",
                                       fix: "Run `rh setup`, or switch on Right Here in System Settings › General › Login Items & Extensions › Finder."))
    }

    @Test func aFinderExtensionThatCrashedIsAWarningInTheWholeRunToo() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0, standardOutput: pluginkitEnabled)]
        let folder = ExtensionCrashes.reportsFolder(home: scene.home)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "report".write(to: folder.appendingPathComponent("FinderExtension-2026-10-15-180000.ips"), atomically: true, encoding: .utf8)
        let extensionCheck = said(await scene.run(), "finder.extension")
        #expect(extensionCheck?.status == .warn)
        #expect(extensionCheck?.detail?.contains("crashed once") == true)
    }

    @Test func aFinderExtensionRegisteredFromSeveralPlacesSaysWhere() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        let second = "     \(AppIdentity.extensionBundleID)(1.0)\tU2\t2026-10-11 23:20:00 +0000\t/Users/x/DerivedData/Right Here.app/Contents/PlugIns/FinderExtension.appex\n"
        scene.answers = [ProcessResult(status: 0, standardOutput: pluginkitEnabled + second)]
        let extensionCheck = said(await scene.run(), "finder.extension")
        #expect(extensionCheck == Said(
            status: .warn,
            detail: "enabled, but registered from 2 locations: /Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex; /Users/x/DerivedData/Right Here.app/Contents/PlugIns/FinderExtension.appex",
            fix: "Run `rh setup` to remove the stale copies."))
    }

    @Test func aConfigWithAnErrorSaysWhichAndHowToCheck() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0)]
        try scene.writeConfig("[general\n")
        let config = said(await scene.run(), "config")
        #expect(config?.status == .fail)
        #expect(config?.detail?.hasPrefix("error: config.toml:1") == true)
        #expect(config?.fix == "Run `rh config validate` and fix the errors.")
    }

    @Test func aConfigWithAWarningCountsItAndExplainsWhatItCosts() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0)]
        try scene.writeConfig("[general]\nterminl = \"ghostty\"\n")
        let config = said(await scene.run(), "config")
        #expect(config == Said(status: .warn, detail: "1 warning(s); run `rh config validate`",
                               fix: "Run `rh config validate`; warnings are usually typos, and what they were meant to set is missing."))
    }

    @Test func aPerMachineOverlayIsNamedAndAConfigThatIsOnlyAnOverlayIsStillOk() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0)]
        try scene.writeConfig("[general]\neditor = \"vscode\"\n", to: scene.paths.localConfigFile)
        let config = said(await scene.run(), "config")
        #expect(config == Said(status: .ok, detail: "none at \(scene.paths.configFile.path); defaults apply", fix: nil,
                               notes: ["merged with the per-machine overlay \(scene.paths.localConfigFile.path)"]))
    }

    @Test func aSymlinkedConfigIsAWarningBecauseTheExtensionCannotFollowIt() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0)]
        let real = scene.home.appendingPathComponent("dotfiles/config.toml")
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\n", to: real)
        try FileManager.default.createSymbolicLink(atPath: scene.paths.configFile.path, withDestinationPath: real.path)
        let config = said(await scene.run(), "config")
        #expect(config == Said(status: .warn, detail: scene.paths.configFile.path, fix: nil,
                               notes: ["config.toml is a symlink, which the Finder extension's sandbox may not be able to follow"]))
    }
}

private let pluginkitDisabled = pluginkitEnabled.replacingOccurrences(of: "+    ", with: "-    ")
private let pluginkitSecondPlace = "     \(AppIdentity.extensionBundleID)(1.0)\tU2\t2026-10-11 23:20:00 +0000\t/Users/x/DerivedData/Right Here.app/Contents/PlugIns/FinderExtension.appex\n"

@Suite("Doctor: looking at the Finder extension alone")
struct DoctorExtensionLookTests {
    @Test func aLookIsOnePluginkitCallAndNothingElse() async {
        // The setup window looks every two seconds while its first-run card waits: no config read, no login shell for the agents.
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: pluginkitEnabled)])
        let check = await Doctor.extensionCheck(runner: runner)
        #expect(check.id == .finderExtension)
        #expect(check.status == .ok)
        #expect(runner.recorded.map(\.executable) == ["/usr/bin/pluginkit"])
    }

    @Test("the check alone says what the whole doctor says of the extension", arguments: [
        "", pluginkitDisabled, pluginkitEnabled, pluginkitEnabled + pluginkitSecondPlace
    ])
    func theSameAsInAWholeRun(output: String) async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0, standardOutput: output)]
        let inTheWholeRun = said(await scene.run(), "finder.extension")
        let alone = said(await Doctor.extensionCheck(runner: FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: output)])))
        #expect(alone != nil)
        #expect(alone == inTheWholeRun)
    }

    @Test func aNewCheckTakesThePlaceOfTheOldOneAndNothingElseChanges() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0, standardOutput: pluginkitDisabled)]
        let before = await scene.run()
        let index = try #require(before.firstIndex { $0.id == .finderExtension })
        #expect(before[index].status == .needsUser)

        let found = await Doctor.extensionCheck(runner: FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: pluginkitEnabled)]))
        let after = before.replacing(found)
        #expect(after.map(\.id) == before.map(\.id), "the same rows in the same order")
        #expect(after[index].status == .ok)
        #expect(after.enumerated().allSatisfy { $0.offset == index || $0.element == before[$0.offset] }, "every other row is as it was")
    }

    @Test func aCheckWithNoRowToTakeThePlaceOfLeavesTheListAsItIs() {
        let rows = [DoctorCheck(.config, status: .ok), DoctorCheck(.finderActivity, status: .ok)]
        #expect(rows.replacing(DoctorCheck(.finderExtension, status: .ok)) == rows)
        #expect([DoctorCheck]().replacing(DoctorCheck(.finderExtension, status: .ok)).isEmpty)
    }

    @Test func anAgentsRowIsToldApartByTheAgent() {
        let rows = [DoctorCheck(.agent("claude"), title: "Claude Code", status: .ok), DoctorCheck(.agent("codex"), title: "Codex", status: .ok)]
        let after = rows.replacing(DoctorCheck(.agent("codex"), title: "Codex", status: .warn))
        #expect(after.map(\.status) == [.ok, .warn])
    }
}
