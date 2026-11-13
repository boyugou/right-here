import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

/// What a third independent review of `rh config sync` found (2026-11-12): what the folder's copy costs every look at it, and a change of what a click starts
/// that the assistant's gate waits for and a pull does not list.
private struct Fixture {
    let root: URL
    let paths: RHPaths
    let remote: URL
    var local: URL { paths.configFile }
    var remoteFile: URL { remote.appendingPathComponent("config.toml") }
    var sync: ConfigSync { ConfigSync(paths: paths) }

    init() throws {
        root = try makeTemporaryDirectory()
        let config = root.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        paths = RHPaths(environment: ["RH_CONFIG_DIR": config.path], home: root.appendingPathComponent("home"))
        remote = root.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
    }

    /// A Mac that pushed `local`, after which the folder's copy became `folder`.
    static func synced(local: String, folder: String) throws -> Fixture {
        let f = try Fixture()
        try local.write(to: f.local, atomically: true, encoding: .utf8)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try folder.write(to: f.remoteFile, atomically: true, encoding: .utf8)
        return f
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

private func seconds(_ body: () throws -> Void) rethrows -> Double {
    let start = ContinuousClock.now
    try body()
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
}

@Suite("Config sync, a third review: what a look at the folder's copy costs (timed)", .serialized)
struct SyncCopyCostTests {
    /// A copy that defines 600 agents of its own (two settings each, under `[agent]` with dotted keys, so the parser's limit of 2048 settings holds 1000 of them): 94 KB, a
    /// tenth of what a config may hold. The builder checks each agent's name against every agent before it, working the comparable form of each one out again
    /// (`ConfigBuilder.agent`, `comparableName` inside `contains(where:)`), which is quadratic. `status`, `pull` and the doctor's sync rows parse the copy three times
    /// (`LaunchCommands.changes` read alone, read with this Mac's own file, and `SyncValidation.check`), the setup window's doctor every time it refreshes, and none
    /// of it needs a pull. Measured in a debug build: 17 s for `status` and 17 s for the doctor; 1000 agents with an accent on each letter of their names, 547 KB, take
    /// 39 s to parse once.
    @Test func aCopyThatDefinesManyAgentsIsLookedAtQuickly() throws {
        var copy = "[agent]\n"
        for index in 0..<600 {
            let name = "Agent \(index) " + String(repeating: "e", count: 100)
            copy += "a\(index).name = \"\(name)\"\na\(index).command = \"tool\"\n"
        }
        #expect(copy.utf8.count < ConfigParser.maxBytes / 10)
        #expect(!ConfigParser.parse(copy).hasErrors, "the copy is a valid config, which status and the doctor read as it is")
        let f = try Fixture.synced(local: "[general]\nterminal = \"terminal\"\n", folder: copy); defer { f.cleanUp() }
        var report: ConfigSync.Report?
        let status = try seconds { report = try f.sync.status() }
        #expect(report?.pendingCommands.isEmpty == false)
        #expect(status < 3.0, "`rh config sync status` took \(status) s for a copy of \(copy.utf8.count) bytes")
        let doctor = seconds { _ = f.sync.doctorChecks() }
        #expect(doctor < 3.0, "the doctor's sync rows took \(doctor) s for a copy of \(copy.utf8.count) bytes")
    }

    /// Whoever writes the folder decides how many files are in it. The doctor's row about conflict copies (`sync.conflict`) names every file called `config <digits>.toml`,
    /// joined into one detail line, which the setup window shows as a row, `rh doctor --json` and the MCP doctor tool hand to an assistant, and the row about the
    /// commands (`sync.commands`) keeps to three and a count. 20,000 such names (230 digits each) made one row of 5 MB in 1 s; 2,000 are enough to show it.
    @Test func theRowAboutConflictCopiesStaysARowHoweverManyTheFolderHolds() throws {
        let f = try Fixture.synced(local: "[general]\nterminal = \"terminal\"\n", folder: "[general]\nterminal = \"terminal\"\n"); defer { f.cleanUp() }
        let digits = String(repeating: "9", count: 230)
        for index in 0..<2_000 {
            FileManager.default.createFile(atPath: f.remote.appendingPathComponent("config \(digits)\(index).toml").path, contents: nil)
        }
        let row = try #require(f.sync.doctorChecks().first { $0.id == .syncConflict })
        let said = Localizer.english.render(sentences: [row.detail].compactMap(\.self) + row.notes)
        #expect(said.utf8.count < 4_096, "the row is \(said.utf8.count) bytes long")
    }
}

@Suite("Config sync, a third review: what a pull leaves")
struct SyncLeftConfigTests {
    /// `pull` validates the copy as it reads alone (`SyncValidation.check`, `ConfigParser.parse`); a click on a Mac that has `config.local.toml` reads the text that
    /// the merge writes (`TOMLEmitter`), and the parser's limit of 2048 settings and tables (`NestingDepth.tomlEntriesExceed`) counts that text. A dotted key is one
    /// setting in the file and a table header plus a key once it is written out, so 1,100 unknown dotted keys (only warnings: a plain pull takes them, no flag) are
    /// 1,103 settings in `config.toml` and 2,201 in the merge: the whole config, this Mac's own file included, then runs as the defaults, and the error blames
    /// `config.toml` for "more than 2048 settings".
    @Test func aCopyThatAPullTakesIsReadAsItWasCheckedOnAMacWithItsOwnFile() throws {
        let local = "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n"
        var copy = local
        for index in 0..<1_100 { copy += "k\(index).a = 1\n" }
        #expect(SyncValidation.check(Data(copy.utf8)).isEmpty, "the copy is one a pull takes")
        let f = try Fixture.synced(local: local, folder: copy); defer { f.cleanUp() }
        try "[general]\nlanguage = \"de\"\n".write(to: f.paths.localConfigFile, atomically: true, encoding: .utf8)
        // Either the pull refuses what this Mac could not read, or this Mac reads what it pulled.
        guard (try? f.sync.pull()) != nil else { return }
        let loaded = ConfigStore.load(paths: f.paths).result
        #expect(!loaded.hasErrors, "\(loaded.diagnostics.filter { $0.severity == .error }.map(\.message))")
        #expect(loaded.config.terminal == "terminal" && loaded.config.enabledAgents == ["claude"] && loaded.config.language == "de",
                "after the pull this Mac runs with the defaults: terminal \(loaded.config.terminal ?? "nil"), agents \(loaded.config.enabledAgents), language \(loaded.config.language ?? "nil")")
    }
}

@Suite("Config sync, a third review: how a click starts an agent")
struct SyncAgentRouteTests {
    private func refusedChanges(_ f: Fixture) -> [LaunchCommands.Change]? {
        do { try f.sync.pull() } catch ConfigSyncError.commandsNeedApproval(let changes, _, _) { return changes } catch { Issue.record("another error: \(error)") }
        return nil
    }

    /// `[agent.<id>] launcher` is listed because "the link and the desktop app start the agent without its command and arguments", which may be what keeps it in
    /// its sandbox (`--sandbox read-only`). An item of the menu or of the Quick Actions that names the launcher (`agent.codex@desktop`, `agent.claude@link`) does the
    /// same for a click on it (`Config.launcher(forAgent:explicit:)` takes the item's launcher first), and `menu.items` and `services.items` are compared by nothing.
    @Test func aCopyThatPutsAnAgentInTheMenuThroughItsDesktopAppIsListedAsTheSettingIs() throws {
        let local = "[general]\nterminal = \"terminal\"\nagents = [\"codex\"]\n\n[agent.codex]\nargs = [\"--sandbox\", \"read-only\"]\n"
        // Control: the setting is asked about.
        let setting = try Fixture.synced(local: local, folder: local + "launcher = \"desktop\"\n"); defer { setting.cleanUp() }
        let listed = try #require(refusedChanges(setting))
        #expect(listed.map(\.place).contains { $0.hasPrefix("[agent.codex] launcher") }, "\(listed.map(\.line))")
        // The item: the same route for a click on it.
        for items in ["[menu]\nitems = [\"agent.codex@desktop\"]\n", "[services]\nitems = [\"agent.codex@desktop\"]\n"] {
            let copy = local + "\n" + items
            #expect(!ConfigParser.parse(copy).hasErrors, "\(ConfigParser.parse(copy).diagnostics.map(\.message))")
            let f = try Fixture.synced(local: local, folder: copy); defer { f.cleanUp() }
            #expect(refusedChanges(f) != nil, "the pull took \(items.debugDescription), which starts Codex without --sandbox read-only, without asking")
        }
        // Claude Code's terminal link does the same: `claude-cli://open?cwd=...` starts it without the plan mode its command keeps it in.
        let claude = "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n\n[agent.claude]\ncommand = \"claude --permission-mode plan\"\n"
        let copy = claude + "\n[menu]\nitems = [\"agent.claude@link\"]\n"
        #expect(!ConfigParser.parse(copy).hasErrors, "\(ConfigParser.parse(copy).diagnostics.map(\.message))")
        let f = try Fixture.synced(local: claude, folder: copy); defer { f.cleanUp() }
        #expect(refusedChanges(f) != nil, "the pull took agent.claude@link, which starts Claude Code without --permission-mode plan, without asking")
    }
}

@Suite("Config sync, a third review: the terminal a click falls back to")
struct SyncDefaultTerminalTests {
    private func parsed(_ text: String) -> Config { ConfigParser.parse(text).config }

    /// This Mac's config defines a terminal under a built-in id that starts through a command template (here: on a build server over ssh), keeps it for
    /// the items that name it, and makes Terminal the default. A copy that only takes `general.terminal` out hands every Open in Terminal and every agent
    /// to the template: with no default, the first installed terminal in the built-in order is used, and the template has Ghostty's place (0) in it. The
    /// assistant's gate waits for exactly this (`ConfigTrust.approvals(changingFrom:to:facts:)`: "turning a terminal off, unsetting the default or naming one that
    /// is not installed can hand every such click to a terminal that starts through a command template, though no setting names it"); the pull lists
    /// nothing, because it reads `[general] terminal` only when that names the template itself.
    @Test func aCopyThatUnsetsTheDefaultTerminalSoThatATemplateTakesItsPlaceIsListed() throws {
        let template = "[[app]]\nid = \"ghostty\"\nname = \"Ghostty\"\nbundle_id = \"com.mitchellh.ghostty\"\nrole = \"terminal\"\nrun_args = [\"/usr/bin/ssh\", \"build-server\", \"cd {dir} && {command}\"]\n"
        let local = "[general]\nterminal = \"terminal\"\n\n" + template
        let copy = template
        #expect(!ConfigParser.parse(local).hasErrors && !ConfigParser.parse(copy).hasErrors)
        let facts = FakeSystemFacts(applications: [
            "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app")
        ])
        // What a click starts: Terminal before, the template after.
        #expect((try? DefaultApps(config: parsed(local), facts: facts).commandTerminal())?.id == "terminal")
        #expect((try? DefaultApps(config: parsed(copy), facts: facts).commandTerminal())?.id == "ghostty")
        #expect(ConfigTrust.approvals(changingFrom: parsed(local), to: parsed(copy), facts: facts).map(\.key).contains("terminal.*.template"))
        let f = try Fixture.synced(local: local, folder: copy); defer { f.cleanUp() }
        var refused = false
        do { try f.sync.pull() } catch ConfigSyncError.commandsNeedApproval { refused = true }
        let now = (try? String(contentsOf: f.local, encoding: .utf8)) ?? ""
        #expect(refused, "the pull made the ssh template the default terminal without asking: \(now)")
    }
}
