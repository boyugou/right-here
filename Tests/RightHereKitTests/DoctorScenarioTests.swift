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

    func run() async -> [DoctorCheck] {
        let facts = FakeSystemFacts(homeDirectory: home, files: files, applications: applications, bundleVersions: bundleVersions, variables: variables)
        let doctor = Doctor(facts: facts, paths: paths, loaded: ConfigStore.load(paths: paths), runner: FakeProcessRunner(results: answers), rhPath: rhPath)
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
        #expect(checks.map(\.id.rawValue) == ["config", "terminal.default", "editor.default", "agents", "claude.link", "finder.runner", "services", "cli.link", "finder.extension", "finder.activity"])
        #expect(said(checks, "config") == Said(status: .warn, detail: "none at \(scene.paths.configFile.path); defaults apply", fix: "Run `rh init`."))
        #expect(said(checks, "terminal.default") == Said(status: .fail, detail: "No terminal is installed.", fix: "Install a terminal or set general.terminal."))
        #expect(said(checks, "editor.default") == Said(status: .warn, detail: "No editor is installed.", fix: "Install an editor or set general.editor."))
        #expect(said(checks, "agents") == Said(status: .warn, detail: "none enabled", fix: "Add agents to general.agents, for example agents = [\"claude\"]."))
        #expect(said(checks, "claude.link") == Said(status: .warn, detail: "handler not installed (only needed for launcher = \"link\")",
                                                    fix: "Start `claude` once and send a prompt; Claude Code registers the handler."))
        #expect(said(checks, "finder.runner") == Said(status: .fail, detail: "not installed; the Finder menu cannot run actions", fix: "Run `rh install --scripts`."))
        #expect(said(checks, "services") == Said(status: .warn, detail: "none installed; Quick Actions and keyboard shortcuts are not available", fix: "Run `rh install --services`."))
        #expect(said(checks, "cli.link") == Said(status: .warn, detail: "no link at \(scene.home.path)/.local/bin/rh", fix: "Run `rh install --cli`."))
        #expect(said(checks, "finder.extension") == Said(status: .fail, detail: "not registered; Finder shows no Right Here menu", fix: "Install Right Here.app, then run `rh install --finder`."))
        #expect(said(checks, "finder.activity") == Said(status: .ok, detail: "none yet; right-click a folder in Finder and choose an action, then run `rh doctor` again", fix: nil))
    }

    @Test func aWorkingMachineIsAllOkAndNamesWhatItFound() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.applications = ["com.mitchellh.ghostty": ghostty, "com.microsoft.VSCode": vscode]
        scene.bundleVersions = ["com.mitchellh.ghostty": "1.3.1"]
        scene.files = [scene.home.appendingPathComponent("Applications/Claude Code URL Handler.app").path]
        scene.variables = ["PATH": "\(scene.home.path)/.local/bin:/usr/bin"]
        scene.answers = [ProcessResult(status: 0, standardOutput: "claude\n"), ProcessResult(status: 0, standardOutput: pluginkitEnabled)]
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
        #expect(said(checks, "finder.extension") == Said(status: .ok, detail: "/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex", fix: nil))
    }

    @Test func anAgentThatTheLoginShellDoesNotFindSaysSoAndHowToRemoveIt() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.applications = ["com.mitchellh.ghostty": ghostty]
        scene.bundleVersions = ["com.mitchellh.ghostty": "1.3.1"]
        scene.answers = [ProcessResult(status: 0), ProcessResult(status: 0)]
        try scene.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        let checks = await scene.run()
        #expect(said(checks, "agent.claude") == Said(status: .warn, detail: "`claude` is not found in your login shell", fix: "Install it, or remove \"claude\" from general.agents."))
        #expect(checks.first { $0.id == .agent("claude") }?.title == "Claude Code")
    }

    @Test func anAgentThatCannotStartSaysWhyAndOffersOtherLaunchers() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0, standardOutput: "claude\n"), ProcessResult(status: 0)]
        try scene.writeConfig("[general]\nagents = [\"claude\"]\n")
        let agent = said(await scene.run(), "agent.claude")
        #expect(agent?.status == .warn)
        #expect(agent?.detail == "No terminal is installed.")
        #expect(agent?.fix == "Choose another terminal with general.terminal, or set launcher = \"link\" or \"desktop\".")
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
        #expect(runner == Said(status: status, detail: detail.replacingOccurrences(of: "{target}", with: target), fix: "Run `rh install --scripts`."))
    }

    @Test func theCommandLinkSaysWhenItsFolderIsNotOnThePath() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0)]
        scene.variables = ["PATH": "/usr/bin"]
        try scene.linkCLI(to: "/opt/rh/bin/rh")
        let link = said(await scene.run(), "cli.link")
        #expect(link == Said(status: .warn, detail: "linked at \(scene.home.path)/.local/bin/rh, but that folder is not on PATH", fix: "Add ~/.local/bin to PATH in your shell profile."))
    }

    @Test func aFinderExtensionThatIsSwitchedOffIsForThePersonToFix() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        scene.answers = [ProcessResult(status: 0, standardOutput: pluginkitEnabled.replacingOccurrences(of: "+    ", with: "-    "))]
        let extensionCheck = said(await scene.run(), "finder.extension")
        #expect(extensionCheck == Said(status: .needsUser, detail: "registered but switched off",
                                       fix: "Run `rh install --finder`, or switch on Right Here in System Settings › General › Login Items & Extensions › Finder."))
    }

    @Test func aFinderExtensionRegisteredFromSeveralPlacesSaysWhere() async throws {
        var scene = try Scene(); defer { scene.cleanUp() }
        let second = "     \(AppIdentity.extensionBundleID)(1.0)\tU2\t2026-10-11 23:20:00 +0000\t/Users/x/DerivedData/Right Here.app/Contents/PlugIns/FinderExtension.appex\n"
        scene.answers = [ProcessResult(status: 0, standardOutput: pluginkitEnabled + second)]
        let extensionCheck = said(await scene.run(), "finder.extension")
        #expect(extensionCheck == Said(
            status: .warn,
            detail: "enabled, but registered from 2 locations: /Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex; /Users/x/DerivedData/Right Here.app/Contents/PlugIns/FinderExtension.appex",
            fix: "Run `rh install --finder` to remove the stale copies."))
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
