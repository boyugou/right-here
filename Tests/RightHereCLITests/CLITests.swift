import Foundation
import Testing
import RightHereCore
import RightHereKit

private final class BundleToken {}

/// Runs the built `rh` with a throwaway config directory and its own HOME-independent paths.
private struct RH {
    let configDirectory: URL
    let binary: URL

    /// A folder standing in for the home directory (`RH_HOME`), for tests of what `rh setup` writes.
    let home: URL?

    /// What the login shell that `rh` starts (to find agent commands) sees as its home: an empty folder, so
    /// the person's own startup files never run during `swift test` (they may be slow, noisy or do things).
    let shellHome: URL

    init(config: String? = nil, trialHome: Bool = false) throws {
        configDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("rh-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        if let config { try config.write(to: configDirectory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8) }
        home = trialHome ? configDirectory.appendingPathComponent("home") : nil
        if let home { try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true) }
        shellHome = configDirectory.appendingPathComponent("shell-home")
        try FileManager.default.createDirectory(at: shellHome, withIntermediateDirectories: true)
        for name in [".zshrc", ".zprofile", ".bashrc", ".bash_profile", ".profile"] {
            try Data().write(to: shellHome.appendingPathComponent(name))
        }
        binary = try Self.locateBinary()
    }

    func cleanUp() { try? FileManager.default.removeItem(at: configDirectory) }

    /// The package builds `rh` as a dependency of this test target, into the folder that holds the test bundle (so
    /// `swift test --scratch-path <folder>` finds its own copy); failing that, the repository's default build folder.
    private static func locateBinary() throws -> URL {
        let manager = FileManager.default
        let bundle = Bundle(for: BundleToken.self).bundleURL
        if bundle.pathExtension == "xctest" {
            let beside = bundle.deletingLastPathComponent().appendingPathComponent("rh")
            if manager.isExecutableFile(atPath: beside.path) { return beside }
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidate = repository.appendingPathComponent(".build/debug/rh")
        guard manager.isExecutableFile(atPath: candidate.path) else { throw CocoaError(.fileNoSuchFile) }
        return candidate
    }

    struct Output {
        var status: Int32
        var standardOutput: String
        var standardError: String
        var json: Any? { try? JSONSerialization.jsonObject(with: Data(standardOutput.utf8)) }
    }

    /// The environment of every `rh` the tests start: its own config and log folders, an empty home for the shell.
    func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // No window can open from a test, whatever a failing action would otherwise show.
        environment["RH_NO_UI"] = "1"
        environment["RH_LOG_DIR"] = configDirectory.appendingPathComponent("logs").path
        environment.removeValue(forKey: "RH_CONFIG")
        environment["HOME"] = shellHome.path
        environment["ZDOTDIR"] = shellHome.path
        if let home {
            // Everything per-user, the config included, goes under the trial home.
            environment["RH_HOME"] = home.path
            environment.removeValue(forKey: "RH_CONFIG_DIR")
            environment.removeValue(forKey: "XDG_CONFIG_HOME")
        } else {
            environment["RH_CONFIG_DIR"] = configDirectory.path
        }
        return environment
    }

    /// Stops a process that is still running after `seconds`, so an `rh` that hangs fails the test it belongs to
    /// (the test then sees a killed process) instead of holding the whole suite for ever.
    func watchdog(_ process: Process, after seconds: TimeInterval = 60) -> DispatchWorkItem {
        let item = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: item)
        return item
    }

    func run(_ arguments: [String]) throws -> Output {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = environment()
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let timer = watchdog(process)
        defer { timer.cancel() }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(status: process.terminationStatus, standardOutput: String(decoding: outData, as: UTF8.self), standardError: String(decoding: errData, as: UTF8.self))
    }
}

@Suite("rh command line")
struct CLITests {
    @Test func versionIsPrinted() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let result = try rh.run(["--version"])
        #expect(result.status == 0)
        #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").count == 3)
    }

    @Test func aPinIsAnAbsolutePathAndTheFileThatKeepsItIsPrivate() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        // "Sources" is relative to where the tests run (the package folder), which has such a folder.
        let pinned = try rh.run(["pin", "Sources", "--json"])
        #expect(pinned.status == 0, "\(pinned.standardError)")
        let path = try #require((pinned.json as? [String: Any])?["pinned"] as? String)
        #expect(path.hasPrefix("/") && path.hasSuffix("/Sources"), "pinned \(path)")
        #expect((try rh.run(["pins", "--json"]).json as? [String]) == [path])
        let attributes = try FileManager.default.attributesOfItem(atPath: rh.configDirectory.appendingPathComponent("state.toml").path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        #expect(try rh.run(["unpin", "Sources"]).standardOutput.hasPrefix("unpinned: /"))
    }

    @Test func helpListsTheMainCommands() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let text = try rh.run(["--help"]).standardOutput
        for command in ["run", "actions", "menu", "config", "doctor", "install", "mcp", "docs", "probe"] {
            #expect(text.contains(command), "help does not mention \(command)")
        }
    }

    @Test func configPathHonorsTheOverride() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let path = try rh.run(["config", "path"]).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(path.hasSuffix("/config.toml"))
        #expect(path.contains("rh-cli-"))
    }

    @Test func validatingAValidConfigSucceedsAndAnInvalidOneFails() throws {
        let good = try RH(config: "[general]\nterminal = \"terminal\"\n"); defer { good.cleanUp() }
        #expect(try good.run(["config", "validate"]).status == 0)

        let bad = try RH(config: "[general]\nterminal = \"ghostyy\"\n"); defer { bad.cleanUp() }
        let result = try bad.run(["config", "validate", "--json"])
        #expect(result.status == 1)
        let report = try #require(result.json as? [String: Any])
        #expect(report["ok"] as? Bool == false)
        let diagnostics = try #require(report["diagnostics"] as? [[String: Any]])
        #expect(diagnostics.first?["path"] as? String == "general.terminal")
    }

    @Test func aSyntaxErrorIsReportedWithALine() throws {
        let rh = try RH(config: "version = 1\n[general\n"); defer { rh.cleanUp() }
        let result = try rh.run(["config", "validate", "--json"])
        #expect(result.status == 1)
        let diagnostics = try #require((result.json as? [String: Any])?["diagnostics"] as? [[String: Any]])
        #expect(diagnostics.first?["line"] as? Int != nil)
    }

    @Test func anArrayThatIsNeverClosedIsReportedAtTheLineWhereItOpened() throws {
        // The usability test's file: six lines, the sixth opens an array and never closes it. The TOML library says
        // "Internal error" and gives a line past the end of the file.
        let text = "version = 1\n\n[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = [\"claude\", \"codex\"\n"
        let rh = try RH(config: text); defer { rh.cleanUp() }
        let result = try rh.run(["config", "validate"])
        #expect(result.status == 1)
        #expect(result.standardOutput.hasPrefix("error: config.toml:6: TOML syntax error: array not closed: missing `]`."), "\(result.standardOutput)")
        #expect(!result.standardOutput.contains("Internal error"))
        let diagnostics = try #require((try rh.run(["config", "validate", "--json"]).json as? [String: Any])?["diagnostics"] as? [[String: Any]])
        #expect(diagnostics.first?["line"] as? Int == 6)
    }

    @Test func aWrongValueSaysWhatItWasAndWhereAndAMissingKeyIsNamed() throws {
        let text = "[general]\nterminal = ghostty\neditor = \"Visual Studio Code\"\ntermnial = 1\n[[app]]\nid = \"x\"\n"
        let rh = try RH(config: text); defer { rh.cleanUp() }
        let lines = try rh.run(["config", "validate"]).standardOutput.split(separator: "\n").map(String.init)
        #expect(lines.count == 4, "\(lines)")
        #expect(lines[0] == "error: config.toml:2 [general.terminal]: expected a string, found text without quotes (write it in quotes: \"ghostty\")", "\(lines[0])")
        #expect(lines[1].hasPrefix("error: config.toml:3 [general.editor]: unknown app \"Visual Studio Code\"") && lines[1].hasSuffix("(did you mean \"vscode\"?)"), "\(lines[1])")
        #expect(lines[2] == "warning: config.toml:4 [general.termnial]: unknown key (did you mean \"terminal\"?)", "\(lines[2])")
        #expect(lines[3] == "error: config.toml:5 [app.1]: an app needs id and name (missing: name)", "\(lines[3])")
        // One bare word in the shared file does not cost the rest of it once there is an overlay.
        try "[general]\nagents = [\"claude\"]\n".write(to: rh.configDirectory.appendingPathComponent("config.local.toml"), atomically: true, encoding: .utf8)
        let layered = try rh.run(["config", "validate"]).standardOutput.split(separator: "\n").map(String.init)
        #expect(layered == lines, "\(layered)")
    }

    @Test func theSchemaIsValidJSON() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let schema = try #require(try rh.run(["config", "schema"]).json as? [String: Any])
        #expect((schema["properties"] as? [String: Any])?["general"] != nil)
    }

    @Test func dryRunPrintsAPlanAndDoesNothing() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let file = rh.configDirectory.appendingPathComponent("a file.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let result = try rh.run(["run", "copy-path.name", "--dry-run", "--json", file.path])
        #expect(result.status == 0)
        let plan = try #require(result.json as? [String: Any])
        #expect(plan["action"] as? String == "copy-path.name")
        let steps = try #require(plan["steps"] as? [[String: Any]])
        #expect(steps.first?["kind"] as? String == "copyToPasteboard")
        #expect(steps.first?["text"] as? String == "a file.txt")
    }

    @Test func anUnknownActionIsAUsageErrorWithAHint() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let result = try rh.run(["run", "explode"])
        #expect(result.status != 0)
        #expect(result.standardError.contains("rh actions"))
    }

    @Test func newFileCreatesAnExclusiveFile() throws {
        let rh = try RH(config: "[new_file]\nthen = \"nothing\"\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(try rh.run(["run", "new-file.md", "--container", folder.path]).status == 0)
        #expect(try rh.run(["run", "new-file.md", "--container", folder.path]).status == 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["untitled 2.md", "untitled.md"])
    }

    @Test func aFileGivenAsTheFolderNeverReachesATerminal() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let script = rh.configDirectory.appendingPathComponent("evil.command")
        try "#!/bin/sh\ntouch /tmp/rh-should-not-run\n".write(to: script, atomically: true, encoding: .utf8)
        // A dry run plans and prints; the plan is where the file would have to appear.
        let result = try rh.run(["run", "open.terminal", "--container", script.path, "--dry-run", "--json"])
        let plan = try #require(result.json as? [String: Any], "no plan was printed: \(result.standardError)")
        let steps = try #require(plan["steps"] as? [[String: Any]])
        let targets = steps.flatMap { ($0["targets"] as? [String]) ?? [] }
        #expect(targets.count == 1)
        #expect(targets.allSatisfy { !$0.hasSuffix("evil.command") }, "the file itself was planned as the terminal's target: \(targets)")
        #expect(targets.first?.hasSuffix(rh.configDirectory.lastPathComponent) == true, "expected the folder around the file: \(targets)")
    }

    @Test func aWarningDoesNotFailValidationUnlessItIsStrict() throws {
        let rh = try RH(config: "[general]\nagnts = [\"codex\"]\n"); defer { rh.cleanUp() }
        let lenient = try rh.run(["config", "validate"])
        #expect(lenient.status == 0)
        #expect(lenient.standardOutput.contains("did you mean \"agents\""))
        let strict = try rh.run(["config", "validate", "--strict"])
        #expect(strict.status == 1)
        let json = try #require(try rh.run(["config", "validate", "--json"]).json as? [String: Any])
        #expect(json["ok"] as? Bool == true)
        #expect(json["clean"] as? Bool == false)
        let diagnostic = try #require((json["diagnostics"] as? [[String: Any]])?.first)
        #expect(diagnostic["replacement"] as? String == "agents")
    }

    @Test func aCleanConfigPassesStrictValidation() throws {
        let rh = try RH(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        #expect(try rh.run(["config", "validate", "--strict"]).status == 0)
    }

    @Test func forcingInitKeepsTheOldFileAsABackup() throws {
        let rh = try RH(config: "# hand-made\n[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        let result = try rh.run(["init", "--force"])
        #expect(result.status == 0)
        #expect(result.standardOutput.contains("the old file is saved as"))
        let backups = try FileManager.default.contentsOfDirectory(atPath: rh.configDirectory.path).filter { $0.hasPrefix("config.toml.bak-") }
        #expect(backups.count == 1)
        let saved = try String(contentsOf: rh.configDirectory.appendingPathComponent(try #require(backups.first)), encoding: .utf8)
        #expect(saved.hasPrefix("# hand-made"))
    }

    @Test func theMenuPreviewSaysWhatItIsFor() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let result = try rh.run(["menu", "--container", "/tmp"])
        #expect(result.standardOutput.hasPrefix("Menu for the folder /tmp (container):\n"))
        #expect(try rh.run(["menu", "--json", "--container", "/tmp"]).json is [Any])
    }

    @Test func aDryRunShowsTheTextAndTheArgumentsItWouldUse() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let copy = try rh.run(["run", "copy-path.ai-mention", "/tmp", "--dry-run"]).standardOutput
        #expect(copy.contains("text: \"@/tmp\""))
        let agent = try rh.run(["run", "agent.codex@terminal", "--dry-run", "--container", "/tmp"])
        // Terminal.app is always installed, so this plans an AppleScript whose arguments are shown.
        #expect(agent.standardOutput.contains("arguments: \"cd /tmp && codex\""))
    }

    /// The value a JSON reader finds in a printed `"..."` literal.
    private func valueRead(from literal: some StringProtocol) throws -> String? {
        try (JSONSerialization.jsonObject(with: Data(("[" + literal + "]").utf8)) as? [String])?.first
    }

    @Test func aDryRunPlanIsNeverCutOffAndEveryValueInItReadsBackAsExactlyThatValue() throws {
        let config = "[[app]]\nid = \"fakeed\"\nname = \"Fake Editor\"\nbundle_id = \"com.apple.finder\"\nrole = \"editor\"\n"
        let rh = try RH(config: config); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("it's \"q\" back\\slash dir")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A name of 120 characters puts the end of the third path well past the 200 characters the plan used to stop at.
        let names = ["a b.txt", "it's \"x\".md", "back\\slash.txt", String(repeating: "n", count: 120) + ".txt"]
        let files = names.map { folder.appendingPathComponent($0) }
        for file in files { try "x".write(to: file, atomically: true, encoding: .utf8) }

        // open: one target to a line, each a quoted string that is exactly the path, and nothing cut.
        let open = try rh.run(["run", "open.app.fakeed", "--dry-run"] + files.map(\.path))
        #expect(open.status == 0, Comment(rawValue: open.standardError))
        let targets = open.standardOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("target: ") }
        #expect(targets.count == files.count, Comment(rawValue: open.standardOutput))
        for (line, file) in zip(targets, files) {
            #expect(try valueRead(from: line.dropFirst("target: ".count)) == file.path, Comment(rawValue: line))
        }

        // copy: the whole text, the paths one to a line, as a string that reads back as the text that would be copied.
        let copy = try rh.run(["run", "copy-path.absolute", "--dry-run"] + files.map(\.path)).standardOutput
        #expect(!copy.contains("…"), Comment(rawValue: copy))
        let text = try #require(copy.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.hasPrefix("text: ") })
        #expect(try valueRead(from: text.dropFirst("text: ".count)) == files.map(\.path).joined(separator: "\n"), Comment(rawValue: copy))
    }

    @Test func agentBypassPermissionsFlagsAndSafeOverride() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let normal = try rh.run(["run", "agent.claude@terminal", "--dry-run", "--container", "/tmp"])
        #expect(normal.standardOutput.contains("arguments: \"cd /tmp && claude\""))

        let bypass = try rh.run(["run", "agent.claude@terminal", "--bypass-permissions", "--dry-run", "--container", "/tmp"])
        #expect(bypass.standardOutput.contains("arguments: \"cd /tmp && claude --dangerously-skip-permissions\""))

        let shortBypass = try rh.run(["run", "agent.agy@terminal", "--bypass-permissions", "--dry-run", "--container", "/tmp"])
        #expect(shortBypass.standardOutput.contains("arguments: \"cd /tmp && agy --dangerously-skip-permissions\""))

        let withArg = try rh.run(["run", "agent.claude@terminal", "--bypass-permissions", "--arg", "--verbose", "--dry-run", "--container", "/tmp"])
        #expect(withArg.standardOutput.contains("arguments: \"cd /tmp && claude --dangerously-skip-permissions --verbose\""))

        let rhWithBypassConfig = try RH(config: "[general]\nbypass_permissions = true\n"); defer { rhWithBypassConfig.cleanUp() }
        let configBypass = try rhWithBypassConfig.run(["run", "agent.codex@terminal", "--dry-run", "--container", "/tmp"])
        #expect(configBypass.standardOutput.contains("arguments: \"cd /tmp && codex --dangerously-bypass-approvals-and-sandbox\""))

        let safeOverride = try rhWithBypassConfig.run(["run", "agent.codex@terminal", "--safe", "--dry-run", "--container", "/tmp"])
        #expect(safeOverride.standardOutput.contains("arguments: \"cd /tmp && codex\""))
    }

    @Test func optionsThatWouldDoNothingAreErrorsAndTheShortBypassFlagIsGone() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        // An action that starts no agent: the options say they do not apply, and nothing is planned.
        let flagged = try rh.run(["run", "copy-path.absolute", "--bypass-permissions", "--safe", "--arg", "--x", "--dry-run", "/tmp"])
        #expect(flagged.status != 0, Comment(rawValue: flagged.standardOutput))
        #expect(flagged.standardError.contains("--bypass-permissions, --safe, --arg can only be used with an AI agent"), Comment(rawValue: flagged.standardError))
        #expect(!flagged.standardOutput.contains("Copy path"))
        let branch = try rh.run(["run", "open.terminal@terminal", "--branch", "x", "--dry-run", "--container", "/tmp"])
        #expect(branch.status != 0 && branch.standardError.contains("--branch can only be used with an AI agent"), Comment(rawValue: branch.standardError))
        // The one-letter spelling of the bypass flag is not an option: a dash-led word is refused, not read as it was.
        let short = try rh.run(["run", "agent.claude@terminal", "-y", "--dry-run", "--container", "/tmp"])
        #expect(short.status != 0, Comment(rawValue: short.standardOutput))
        #expect(short.standardError.contains("need -- before them"), Comment(rawValue: short.standardError))
        // A preset keeps its agent's prompts on, so the flag would do nothing: it is refused.
        let preset = try rh.run(["run", "preset.review", "--bypass-permissions", "--dry-run", "/tmp"])
        #expect(preset.status != 0 && preset.standardError.contains("does not apply to a preset"), Comment(rawValue: preset.standardError))
        let together = try rh.run(["run", "agent.claude@terminal", "--bypass-permissions", "--safe", "--dry-run", "--container", "/tmp"])
        #expect(together.status != 0 && together.standardError.contains("cannot be used together"), Comment(rawValue: together.standardError))
    }

    @Test func bypassPermissionsReachesTheAgentEvenWhenItsConfigSwitchesThePromptsOff() throws {
        // A config that says `bypass_permissions = false` for the agent used to swallow `--bypass-permissions` without a word.
        let rh = try RH(config: "[agent.claude]\nbypass_permissions = false\n[agent.codex]\nbypass_permissions = true\n"); defer { rh.cleanUp() }
        let claude = try rh.run(["run", "agent.claude@terminal", "--bypass-permissions", "--dry-run", "--container", "/tmp"])
        #expect(claude.standardOutput.contains("arguments: \"cd /tmp && claude --dangerously-skip-permissions\""), Comment(rawValue: claude.standardOutput))
        // And `--safe` turns the prompts on for one run, whatever the config says for that agent.
        let codex = try rh.run(["run", "agent.codex@terminal", "--safe", "--dry-run", "--container", "/tmp"])
        #expect(codex.standardOutput.contains("arguments: \"cd /tmp && codex\""), Comment(rawValue: codex.standardOutput))
    }

    @Test func aDryRunThatFailsIsNotWrittenToTheLogAndARealOneIs() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let log = rh.configDirectory.appendingPathComponent("logs/rh.log")
        #expect(try rh.run(["run", "open.terminal", "--dry-run", "/nonexistent-rh-test-folder"]).status == 1)
        #expect(!FileManager.default.fileExists(atPath: log.path), "a question answered on the command line is not a failure")
        #expect(try rh.run(["run", "open.terminal", "/nonexistent-rh-test-folder"]).status == 1)
        #expect(try String(contentsOf: log, encoding: .utf8).contains("open.terminal:"))
    }

    @Test func aDashArgumentIsSaidOnceAndAMisspeltCommandIsNotAnsweredWithTheHelp() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let dash = try rh.run(["run", "copy-path.absolute", "-dash.txt"])
        #expect(dash.status == 64 && dash.standardError.contains("need -- before them"), Comment(rawValue: dash.standardError))
        #expect(!dash.standardOutput.contains("OVERVIEW"))
        let misspelt = try rh.run(["runn", "copy-path.absolute"])
        #expect(misspelt.status == 64 && misspelt.standardError.contains("Did you mean \"run\"?"), Comment(rawValue: misspelt.standardError))
        let withHelp = try rh.run(["nosuchcmd", "--help"])
        #expect(withHelp.status == 64 && !withHelp.standardOutput.contains("OVERVIEW"), Comment(rawValue: withHelp.standardOutput))
        // The spelling the message gives works: the file is planned, not the help printed.
        let file = rh.configDirectory.appendingPathComponent("-dash.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let fixed = try rh.run(["run", "copy-path.name", "--dry-run", "--", file.path])
        #expect(fixed.status == 0 && fixed.standardOutput.contains("-dash.txt"), Comment(rawValue: fixed.standardError))
    }

    /// A git repository with a folder `sub/deeper` and one commit, in the test's own folder. Its worktrees are made under it too.
    private func repository(_ rh: RH) throws -> URL {
        let folder = rh.configDirectory.appendingPathComponent("repo")
        let deeper = folder.appendingPathComponent("sub/deeper")
        try FileManager.default.createDirectory(at: deeper, withIntermediateDirectories: true)
        try "readme".write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "a".write(to: deeper.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try git(["init", "-q"], in: folder)
        _ = try git(["add", "-A"], in: folder)
        _ = try git(["commit", "-q", "-m", "initial"], in: folder)
        return folder
    }

    private func git(_ arguments: [String], in folder: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path, "-c", "commit.gpgsign=false", "-c", "user.name=Test", "-c", "user.email=test"] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// A terminal that runs `touch` (no window) and one that runs `false`, and an agent called `marker` (which is not installed here).
    private let worktreeConfig = """
    [general]
    agents = ["marker"]
    [[app]]
    id = "faketerm"
    name = "Fake"
    bundle_id = "com.apple.finder"
    role = "terminal"
    run_args = ["/usr/bin/touch", "{dir}/ran-{command}"]
    [[app]]
    id = "failterm"
    name = "Failing"
    bundle_id = "com.apple.finder"
    role = "terminal"
    run_args = ["/usr/bin/false", "{command}"]
    [agent.marker]
    name = "marker"
    command = "marker"
    """

    @Test func aWorktreeRunStartsTheAgentInTheFolderThatWasNamedNotAtTheRootOfTheWorktree() throws {
        let rh = try RH(config: worktreeConfig); defer { rh.cleanUp() }
        let repo = try repository(rh)
        let result = try rh.run(["run", "agent.marker@faketerm", "--worktree", "--branch", "feature-x", "--container", repo.appendingPathComponent("sub/deeper").path])
        #expect(result.status == 0, Comment(rawValue: result.standardError))
        let made = repo.appendingPathComponent(".right-here/worktrees/feature-x/sub/deeper")
        #expect(FileManager.default.fileExists(atPath: made.appendingPathComponent("ran-marker").path), "the agent did not start in the folder that was named")
        #expect(!FileManager.default.fileExists(atPath: repo.appendingPathComponent("sub/deeper/ran-marker").path), "the repository's own folder was used")
    }

    @Test func aWorktreeDryRunShowsTheFolderInsideTheWorktreeAndMakesNothing() throws {
        let rh = try RH(config: worktreeConfig); defer { rh.cleanUp() }
        let repo = try repository(rh)
        let result = try rh.run(["run", "agent.marker@faketerm", "--worktree", "--dry-run", "--container", repo.appendingPathComponent("sub/deeper").path])
        #expect(result.status == 0, Comment(rawValue: result.standardError))
        #expect(result.standardOutput.contains(".right-here/worktrees/rh-<auto-branch>/sub/deeper/ran-marker"), Comment(rawValue: result.standardOutput))
        #expect(result.standardError.contains("would create the worktree"), Comment(rawValue: result.standardError))
        // The dry run asks the login shell about the agent: the marker is not installed, and the plan says so.
        #expect(result.standardOutput.contains("marker is not found by your login shell"), Comment(rawValue: result.standardOutput))
        #expect(try git(["worktree", "list"], in: repo).split(separator: "\n").count == 1, "a dry run made a worktree")
    }

    @Test func aRunThatFailsAfterItMadeTheWorktreeLeavesNoWorktreeAndNoBranch() throws {
        let rh = try RH(config: worktreeConfig); defer { rh.cleanUp() }
        let repo = try repository(rh)
        let result = try rh.run(["run", "agent.marker@failterm", "--worktree", "--branch", "feature-y", "--container", repo.appendingPathComponent("sub/deeper").path])
        #expect(result.status == 1, Comment(rawValue: result.standardError))
        #expect(!FileManager.default.fileExists(atPath: repo.appendingPathComponent(".right-here/worktrees/feature-y").path), "the failed run left its worktree behind")
        #expect(try git(["branch", "--list", "feature-y"], in: repo).isEmpty, "the failed run left its branch behind")
        #expect(result.standardError.contains("was removed again"), Comment(rawValue: result.standardError))
    }

    @Test func aRunRefusedBeforeAnythingIsDoneLeavesNoWorktreeAndNoBranch() throws {
        let rh = try RH(config: worktreeConfig); defer { rh.cleanUp() }
        let repo = try repository(rh)
        let result = try rh.run(["run", "agent.marker@nosuchterm", "--worktree", "--branch", "feature-z", "--container", repo.appendingPathComponent("sub/deeper").path])
        #expect(result.status == 1)
        #expect(!FileManager.default.fileExists(atPath: repo.appendingPathComponent(".right-here/worktrees").path), "a refused run made the worktrees folder")
        #expect(try git(["branch", "--list", "feature-z"], in: repo).isEmpty)
        #expect(try git(["worktree", "list"], in: repo).split(separator: "\n").count == 1)
    }

    @Test("the checker knows exactly the options that run and menu have, so a new option cannot slip past it")
    func theCheckerKnowsTheOptionsOfRunAndMenu() throws {
        for (command, known) in [("run", InvocationCheck.runOptions), ("menu", InvocationCheck.menuOptions)] {
            let rh = try RH(); defer { rh.cleanUp() }
            let help = try rh.run([command, "--help"]).standardOutput
            // Every word of the help that is an option (a dash, then letters): the ones the help names, prose included.
            let words = help.split { !($0.isLetter || $0 == "-") }.map(String.init)
            let named = Set(words.filter { $0.hasPrefix("-") && $0.contains(where: \.isLetter) })
            let checked = known.flags.union(known.values)
            #expect(checked.isSubset(of: named), "\(command): the checker knows \(checked.subtracting(named)), which the help does not name")
            #expect(named.subtracting(checked).isEmpty, "\(command): the help names \(named.subtracting(checked)), which the checker does not know and would refuse")
        }
    }

    @Test func aPresetDryRunShowsTheQuotedPromptAndAHostileNameIsRefused() throws {
        let rh = try RH(config: "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let plain = folder.appendingPathComponent("it's here.txt")
        let hostile = folder.appendingPathComponent("two\nlines.txt")
        for file in [plain, hostile] { try "x".write(to: file, atomically: true, encoding: .utf8) }

        let ok = try rh.run(["run", "preset.review", "--dry-run", plain.path])
        #expect(ok.status == 0, Comment(rawValue: ok.standardError))
        // The dry run shows the argument as a JSON string, so the quote of `@"it's here.txt"` is `\"` and each backslash is `\\`
        // (the shell's own `'\''` is therefore `'\\''`).
        #expect(ok.standardOutput.contains(#"claude 'Review @\"it'\\''s here.txt\" for bugs"#), Comment(rawValue: ok.standardOutput))

        let refused = try rh.run(["run", "preset.review", "--dry-run", hostile.path])
        #expect(refused.status != 0)
        #expect(refused.standardError.contains("the file \"two\\nlines.txt\" cannot be named in the prompt of preset \"review\""), Comment(rawValue: refused.standardError))
        #expect(!refused.standardOutput.contains("claude '"))

        let noFiles = try rh.run(["run", "preset.review", "--dry-run", "--container", folder.path])
        #expect(noFiles.status != 0 && noFiles.standardError.contains("select one or more files"), Comment(rawValue: noFiles.standardError))

        let actions = try rh.run(["actions"]).standardOutput
        #expect(actions.contains("preset.review") && actions.contains("preset.tests"))
        let agents = try #require(try rh.run(["agents", "--json"]).json as? [[String: Any]])
        #expect(agents.first { $0["id"] as? String == "claude" }?["promptArgument"] as? String == "positional")
    }

    @Test func aNewFileTakesItsNameInTheLanguageRhIsGivenAndInEnglishOtherwise() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let english = try rh.run(["run", "new-file.md", "--dry-run", "--container", folder.path])
        #expect(english.standardOutput.contains("/untitled.md"), Comment(rawValue: english.standardOutput))
        let german = try rh.run(["run", "new-file.md", "--dry-run", "--language", "de-DE", "--language", "en-US", "--container", folder.path])
        #expect(german.standardOutput.contains("/unbenannt.md"), Comment(rawValue: german.standardOutput))
    }

    @Test func aRefusalNamesTheFileOrFolderThatIsWrongAndQuotesItOnce() throws {
        let rh = try RH(config: "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("nl\nfolder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = rh.configDirectory.appendingPathComponent("two\nlines.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        // Terminal types the folder, so a line break in its name is refused: the message says it is the folder, once quoted.
        let typed = try rh.run(["run", "agent.claude@terminal", "--dry-run", "--container", folder.path])
        #expect(typed.status == 1)
        #expect(typed.standardError.hasPrefix("error: The folder \"\(folder.path)".replacingOccurrences(of: "\n", with: "\\n")), Comment(rawValue: typed.standardError))
        #expect(!typed.standardError.contains("\"\""), Comment(rawValue: typed.standardError))

        // A file in the prompt of a preset: the file is named, and the prompt (which is fine) is not blamed.
        let preset = try rh.run(["run", "preset.review@terminal", "--dry-run", file.path])
        #expect(preset.status == 1)
        #expect(preset.standardError.contains("the file \"two\\nlines.txt\" cannot be named in the prompt of preset \"review\""), Comment(rawValue: preset.standardError))
        #expect(!preset.standardError.contains("The prompt of preset"), Comment(rawValue: preset.standardError))
    }

    @Test func rhAgentsSaysAnEnabledAgentThatItsShellDoesNotFindIsNotFound() throws {
        // `rh docs sync` said an agent that is not installed is skipped by the menu; it is not, so the list has to say which is which.
        let rh = try RH(config: "[general]\nagents = [\"ghostly\"]\n[agent.ghostly]\nname = \"Ghostly\"\ncommand = \"rh-test-no-such-command\"\n"); defer { rh.cleanUp() }
        let line = try #require(try rh.run(["agents"]).standardOutput.split(separator: "\n").first { $0.hasPrefix("ghostly") })
        #expect(line.hasSuffix("enabled, not found"), "\(line)")
        let menu = try rh.run(["menu", "--container", rh.configDirectory.path]).standardOutput
        #expect(menu.contains("Ghostly Here"), "the menu cannot look, so it lists the agent anyway")
        let sync = try rh.run(["docs", "sync"]).standardOutput.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(!sync.contains("an app or agent that is not installed is skipped"), "the agent half of that sentence was wrong")
        #expect(sync.contains("`enabled, not found`"))
    }

    @Test func theAgentsTheIntentsOfferAreReadFromWhatRhAgentsPrints() throws {
        let rh = try RH(config: "[general]\nagents = [\"claude\"]\n"); defer { rh.cleanUp() }
        let result = try rh.run(["agents", "--json"])
        #expect(result.status == 0, Comment(rawValue: result.standardError))
        let rows = try #require(result.json as? [[String: Any]])
        #expect(!rows.isEmpty && rows.allSatisfy { $0["foundInShell"] is Bool }, "rh agents asks the login shell about every command")
        // The App Intents decode this very output, and a row they cannot read would leave their picker empty without a word.
        #expect(IntentCatalog.agents(fromJSON: Data(result.standardOutput.utf8)).contains(IntentChoice(id: "claude", name: "Claude Code")))
    }

    @Test("what a menu click sends is accepted by the real rh, for every kind of Finder menu", arguments: [
        FinderMenuKind.items, .container, .sidebar, .toolbar
    ])
    func theExtensionsArgumentsAreAcceptedByRh(kind: FinderMenuKind) throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("my folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [URL] = []
        for name in ["a b.txt", "-dash.txt", "日本語 é.md"] {
            let file = folder.appendingPathComponent(name)
            try "x".write(to: file, atomically: true, encoding: .utf8)
            files.append(file)
        }
        // The context is built the way the extension builds it, then turned into the runner's arguments.
        let context = HereContext.finder(kind: kind, selected: files, targeted: folder)
        // Terminal.app is on every Mac, so these plan without anything else installed.
        for action in ["open.terminal@terminal", "agent.claude@terminal", "copy-path.absolute", "copy-path.git-relative", "new-file.md", "reveal"] {
            var arguments = RunnerArguments.run(actionID: action, context: context)
            arguments.insert(contentsOf: ["--dry-run", "--json"], at: 1)
            let result = try rh.run(arguments)
            // An action may be unavailable (a new file needs a single item); what must never happen is a
            // usage error, which is what a mismatch between the extension and the CLI would look like.
            #expect(result.status != 64, "rh rejected the extension's arguments for \(action) from the \(kind) menu: \(arguments) \(result.standardError)")
            if result.status == 0 { #expect(result.json != nil, "no plan for \(action): \(result.standardOutput)") }
        }
        // And the two that always plan for a folder or a selection do succeed.
        for action in ["open.terminal@terminal", "copy-path.absolute", "reveal"] {
            var arguments = RunnerArguments.run(actionID: action, context: context)
            arguments.insert(contentsOf: ["--dry-run", "--json"], at: 1)
            let result = try rh.run(arguments)
            #expect(result.status == 0, "\(action) from the \(kind) menu failed: \(result.standardError)")
        }
    }

    @Test func theCommandAServiceRunsIsAcceptedByRh() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("a service folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A Quick Action runs `rh run --alert <id> --origin services -- "$@"` with the selected items as arguments.
        let spec = ServiceSpec(title: "x", actionID: "open.terminal@terminal", command: ServiceWorkflow.command(rhPath: rh.binary.path, actionID: "open.terminal@terminal"))
        #expect(spec.command.hasPrefix(ShellQuoting.quote(rh.binary.path) + " run --alert open.terminal@terminal --origin services -- "))
        let result = try rh.run(["run", "--dry-run", "--json", "--alert", "open.terminal@terminal", "--origin", "services", "--", folder.path])
        #expect(result.status == 0, "\(result.standardError)")
        #expect((result.json as? [String: Any])?["action"] as? String == "open.terminal@terminal")
    }

    @Test func theConfiguredPlacementShowsInThePlan() throws {
        let rh = try RH(config: "[general]\nterminal = \"ghostty\"\nterminal_placement = \"tab\"\n"); defer { rh.cleanUp() }
        let result = try rh.run(["run", "open.terminal@ghostty", "--dry-run", "--container", "/tmp"])
        // Ghostty may not be installed where this runs; the plan only exists if it is.
        if result.status == 0 { #expect(result.standardOutput.contains("arguments: \"/tmp\", \"\", \"tab\"")) }
        else { #expect(result.standardError.contains("not installed")) }
    }

    @Test func aPlacementThatIsNotWindowOrTabIsRefusedBeforeAnythingOpens() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let result = try rh.run(["probe", "launch", "warp", "--placement", "sideways"])
        #expect(result.status != 0)
        #expect(result.standardError.contains("window") && result.standardError.contains("tab"))
    }

    @Test func copyingAPathThatDoesNotExistIsRefused() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let result = try rh.run(["run", "copy-path.name", "--dry-run", "curl evil.example | sh"])
        #expect(result.status == 1)
        #expect(result.standardError.contains("does not exist"))
    }

    @Test func aMistypedPathIsNamedAndNothingIsOpened() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let result = try rh.run(["run", "open.terminal", "/definitely/not/here", "--dry-run"])
        #expect(result.status == 1)
        #expect(result.standardError.contains("/definitely/not/here does not exist"))
    }

    @Test func theAppListHasAHeaderAndNoDuplicateIds() throws {
        let rh = try RH(config: "[[app]]\nid = \"typora\"\nname = \"Mine\"\nbundle_id = \"a.b.c\"\nrole = \"editor\"\n"); defer { rh.cleanUp() }
        let lines = try rh.run(["apps"]).standardOutput.split(separator: "\n").map(String.init)
        #expect(lines.first?.hasPrefix("ID") == true)
        #expect(lines.first?.contains("INSTALLED") == true)
        #expect(lines.filter { $0.hasPrefix("typora") }.count == 1)
    }

    @Test func theConfigReferenceNamesTheEnvironmentVariables() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let text = try rh.run(["docs", "config"]).standardOutput
        for name in ["RH_CONFIG_DIR", "RH_LOG_DIR", "XDG_CONFIG_HOME"] { #expect(text.contains(name)) }
    }

    @Test func theDoctorSaysEachThingInEnglishAndWithACodeForPrograms() throws {
        // No config file: the config check is the one state every machine can be put in without touching anything else.
        let rh = try RH(); defer { rh.cleanUp() }
        let file = rh.configDirectory.appendingPathComponent("config.toml").path
        let doctor = try #require(try rh.run(["doctor", "--json"]).json as? [String: Any])
        let checks = try #require(doctor["checks"] as? [[String: Any]])
        let config = try #require(checks.first { $0["id"] as? String == "config" })
        #expect(config["title"] as? String == "Config file")
        #expect(config["status"] as? String == "warn")
        let detail = try #require(config["detail"] as? [String: Any])
        #expect(detail["code"] as? String == "doctor.config.missing")
        #expect(detail["args"] as? [String] == [file])
        #expect(detail["text"] as? String == "none at \(file); defaults apply")
        let fix = try #require(config["fix"] as? [String: Any])
        #expect(fix["code"] as? String == "doctor.fix.runSetup")
        #expect(fix["text"] as? String == "Run `rh setup`.")
        // The same data, written for a person.
        let lines = try rh.run(["doctor"]).standardOutput.split(separator: "\n").map(String.init)
        let at = try #require(lines.firstIndex(of: "[warn] Config file: none at \(file); defaults apply"))
        #expect(lines[at + 1] == "       fix: Run `rh setup`.")
    }

    // The apps below use a made-up bundle id, so what is installed on the Mac that runs the tests does not change the answers.
    private static let ghostEditor = "[[app]]\nid = \"ghost\"\nname = \"Ghost\"\nbundle_id = \"com.example.not-installed\"\nrole = \"editor\"\n"

    @Test func menuExplainSaysWhatTheMenuLeavesOutAndTheMenuItselfIsUnchanged() throws {
        let rh = try RH(config: "[general]\nagents = []\n[menu]\nitems = [\"open.app.ghost\", \"agents\", \"copy-path\"]\n" + Self.ghostEditor); defer { rh.cleanUp() }
        let folder = rh.configDirectory.path
        let plain = try rh.run(["menu", "--container", folder])
        #expect(plain.status == 0 && !plain.standardOutput.contains("Left out"), "--explain is the only thing that adds the block")
        let explained = try rh.run(["menu", "--container", folder, "--explain"])
        #expect(explained.status == 0, "\(explained.standardError)")
        #expect(explained.standardOutput.hasPrefix(plain.standardOutput.trimmingCharacters(in: .newlines)), "the menu comes first, as it is")
        let text = explained.standardOutput
        #expect(text.contains("\nLeft out of this menu:\n  Open in Ghost: Ghost is not installed.\n  Agents: none is enabled; general.agents lists none."), "\(text)")
        // JSON keeps its old shape (an array of entries) unless --explain asks for the notes.
        #expect(try rh.run(["menu", "--container", folder, "--json"]).json is [Any])
        let json = try #require(try rh.run(["menu", "--container", folder, "--explain", "--json"]).json as? [String: Any])
        #expect(json["menu"] is [Any])
        let notes = try #require(json["notes"] as? [[String: Any]])
        #expect(notes.contains { $0["kind"] as? String == "leftOut" && $0["entry"] as? String == "Open in Ghost" })
    }

    @Test func anEmptyMenuIsSaidWithAHintAndExplainedWithItsReasons() throws {
        let rh = try RH(config: "[general]\nagents = []\n[copy_path]\nstyles = []\n[menu]\nitems = [\"agents\", \"presets\", \"agents-more\", \"copy-path\"]\n"); defer { rh.cleanUp() }
        let plain = try rh.run(["menu", "--container", rh.configDirectory.path])
        #expect(plain.standardOutput.contains("(empty: `rh menu --explain` says why each entry is left out)"), "\(plain.standardOutput)")
        let explained = try rh.run(["menu", "--container", rh.configDirectory.path, "--explain"]).standardOutput
        #expect(explained.contains("  Agents: none is enabled; general.agents lists none.") && explained.contains("  Copy Path: copy_path.styles lists no style."), "\(explained)")
        // And the config check says the same, as a warning that `--strict` turns into a failure.
        let validate = try rh.run(["config", "validate"])
        #expect(validate.status == 0)
        #expect(validate.standardOutput.contains("warning: config.toml [menu]: the Finder menu would be empty for a folder: Agents: none is enabled; general.agents lists none; Copy Path: copy_path.styles lists no style"), "\(validate.standardOutput)")
        #expect(try rh.run(["config", "validate", "--strict"]).status == 1)
        let json = try #require(try rh.run(["config", "validate", "--json"]).json as? [String: Any])
        #expect((json["diagnostics"] as? [[String: Any]])?.contains { $0["path"] as? String == "menu" } == true)
        // The doctor has a row for it; a healthy config has none and validates clean.
        let doctor = try #require(try rh.run(["doctor", "--json"]).json as? [String: Any])
        let row = try #require((doctor["checks"] as? [[String: Any]])?.first { $0["id"] as? String == "finder.menu" })
        #expect(row["status"] as? String == "warn")
        let healthy = try RH(config: "[general]\nterminal = \"terminal\"\n"); defer { healthy.cleanUp() }
        #expect(try healthy.run(["config", "validate", "--strict"]).status == 0)
        // An empty list of entries is a warning of the parser's already; the menu check does not say it a second time.
        let listless = try RH(config: "[menu]\nitems = []\n"); defer { listless.cleanUp() }
        let listlessJSON = try #require(try listless.run(["config", "validate", "--json"]).json as? [String: Any])
        let messages = (listlessJSON["diagnostics"] as? [[String: Any]])?.compactMap { $0["message"] as? String } ?? []
        #expect(messages.filter { $0.contains("Finder menu") }.count == 1, "\(messages)")
    }

    @Test func aFolderMenuNeedsAFolderGivenAsContainer() throws {
        // `rh menu --origin container <folder>` printed "Menu for the folder ?": the path is a selection, not the folder.
        let rh = try RH(); defer { rh.cleanUp() }
        let folder = rh.configDirectory.path
        let asPath = try rh.run(["menu", "--origin", "container", folder])
        #expect(asPath.status != 0 && asPath.standardError.contains("needs --container <folder>"), "\(asPath.standardError)")
        #expect(!asPath.standardOutput.contains("Menu for the folder ?"))
        let none = try rh.run(["menu", "--origin", "container"])
        #expect(none.status != 0 && none.standardError.contains("needs --container <folder>"), "\(none.standardError)")
        #expect(try rh.run(["menu", "--origin", "container", "--container", folder]).status == 0)
        // `--container` is the folder being viewed: a file there is refused, and the way to preview a selection is named.
        let file = rh.configDirectory.appendingPathComponent("a-file.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let asFile = try rh.run(["menu", "--container", file.path])
        #expect(asFile.status != 0 && asFile.standardError.contains("is a file") && asFile.standardError.contains("as a path"), "\(asFile.standardError)")
        #expect(try rh.run(["menu", "--", file.path]).status == 0)
    }

    @Test func underATrialHomeTheDoctorSaysSoOnStandardErrorAndItsJSONStaysADocument() throws {
        // `rh doctor` mixes this home's files (config, log, runner script) with the system-wide extension registration, which a
        // reader of the rows cannot tell apart unless the report says that RH_HOME is active.
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        let json = try rh.run(["doctor", "--json"])
        #expect(json.json as? [String: Any] != nil, "standard output is not one JSON document: \(json.standardOutput.prefix(200))")
        #expect(json.standardError.contains("RH_HOME is set") && json.standardError.contains(home.path), "\(json.standardError)")
        let text = try rh.run(["doctor"])
        #expect(text.standardError.contains("RH_HOME is set") && !text.standardOutput.contains("RH_HOME"))
    }

    @Test func aFirstInstallWritesEverythingUnderTheTrialHomeAndTheServicesFollowTheNewConfig() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        let install = try rh.run(["setup"])
        #expect(install.status == 0, "\(install.standardError)")
        let manager = FileManager.default
        #expect(manager.fileExists(atPath: home.appendingPathComponent(".config/right-here/config.toml").path))
        #expect(manager.fileExists(atPath: home.appendingPathComponent("Library/Application Scripts/com.boyugou.righthere.FinderExtension/rh-run").path))
        #expect((try? manager.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".local/bin/rh").path)) != nil)
        let services = try manager.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Services").path).filter { $0.hasPrefix("Right Here - ") }
        #expect(!services.isEmpty)
        // The doctor compares the installed Services with what the config just written asks for. If
        // they were built from the config as it was before `rh setup` created it, agents would be missing.
        let doctor = try #require(try rh.run(["doctor", "--json"]).json as? [String: Any])
        let checks = try #require(doctor["checks"] as? [[String: Any]])
        let servicesCheck = try #require(checks.first { $0["id"] as? String == "services" })
        #expect(servicesCheck["status"] as? String == "ok", "\(servicesCheck)")
    }

    @Test func uninstallUnderATrialHomeRemovesItsFilesAndLeavesTheSystemWideExtensionAlone() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        #expect(try rh.run(["setup"]).status == 0)
        let result = try rh.run(["uninstall"])
        #expect(result.status == 0)
        #expect(result.standardOutput.contains("left alone"))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Scripts/com.boyugou.righthere.FinderExtension/rh-run").path))
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Services").path)) ?? []
        #expect(remaining.filter { $0.hasPrefix("Right Here - ") }.isEmpty)
    }

    @Test func uninstallKeepsGoingAfterAFailedStepAndSaysWhatFailed() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        #expect(try rh.run(["setup"]).status == 0)
        // A runner script that cannot be removed (its folder is read-only) must not keep the Services installed.
        let scripts = home.appendingPathComponent("Library/Application Scripts/com.boyugou.righthere.FinderExtension")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: scripts.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scripts.path) }
        let result = try rh.run(["uninstall"])
        #expect(result.status == 1, "status \(result.status)")
        #expect(result.standardError.contains("runner script"))
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Services").path)) ?? []
        #expect(remaining.filter { $0.hasPrefix("Right Here - ") }.isEmpty, "the Services were left installed")
    }

    @Test func uninstallRemovesTheCommandLinkItMadeAndLeavesSomeoneElsesAlone() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        let link = home.appendingPathComponent(".local/bin/rh")
        #expect(try rh.run(["setup"]).status == 0)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
        let ours = try rh.run(["uninstall"])
        #expect(ours.standardOutput.contains("Removed the command link"))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == nil, "its own link should be gone")

        // A link to some other program that happens to be called rh is not Right Here's to remove.
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/bin/ls")
        let foreign = try rh.run(["uninstall"])
        #expect(foreign.standardOutput.contains("Left the command link alone"))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "/bin/ls")
    }

    @Test func aRealFileAtTheCommandLinkMakesSetupReportAProblemButFinishTheRest() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
        try "mine".write(to: home.appendingPathComponent(".local/bin/rh"), atomically: true, encoding: .utf8)
        let result = try rh.run(["setup"])
        #expect(result.status == 1)
        #expect(result.standardOutput.contains("Command link: failed") && result.standardOutput.contains("left alone"), "\(result.standardOutput)")
        #expect(result.standardError.contains("Finished with 1 problem(s)"), "\(result.standardError)")
        #expect(try String(contentsOf: home.appendingPathComponent(".local/bin/rh"), encoding: .utf8) == "mine")
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".config/right-here/config.toml").path), "the other steps still ran")
    }

    /// A terminal that cannot be installed (its bundle id does not exist), so a probe aimed at it can never start a
    /// window or send an Apple event, even if the guard that is being tested regresses.
    private static let ghostTerminal = """
    [[app]]
    id = "ghost"
    name = "Ghost"
    bundle_id = "com.example.right-here-test-never-installed"
    role = "terminal"
    """

    @Test func aProbeRequestThatWasLeftBehindIsRemovedAndNothingRuns() throws {
        let rh = try RH(config: Self.ghostTerminal); defer { rh.cleanUp() }
        let marker = rh.configDirectory.appendingPathComponent(".probe")
        try "launch".write(to: marker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3_600)], ofItemAtPath: marker.path)
        let result = try rh.run(["probe", "launch", "ghost", "--from-extension"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(result.standardOutput.isEmpty, "the probe ran: \(result.standardOutput)")
        #expect(!FileManager.default.fileExists(atPath: marker.path), "a stale request must not stay behind")
        let log = rh.configDirectory.appendingPathComponent("logs/rh.log")
        #expect(!((try? String(contentsOf: log, encoding: .utf8)) ?? "").contains("probe launch"))
        // And with no request at all there is nothing to run either.
        #expect(try rh.run(["probe", "automation", "ghost", "--from-extension"]).standardOutput.isEmpty)
    }

    @Test func aDanglingSymlinkDoesNotBlockANewFileForever() throws {
        // `then = "nothing"`: the default would reveal the new file, which opens a Finder window while the tests run.
        let rh = try RH(config: "[new_file]\nthen = \"nothing\"\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("untitled.txt").path, withDestinationPath: "/nowhere/at/all")
        let result = try rh.run(["run", "new-file.txt", "--container", folder.path])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("untitled 2.txt").path))
    }

    @Test func theTroubleshootingGuideIsServedByTheCommandLine() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let listing = try rh.run(["docs"]).standardOutput
        #expect(listing.contains("troubleshooting"))
        let guide = try rh.run(["docs", "troubleshooting"])
        #expect(guide.status == 0)
        #expect(guide.standardOutput.contains("rh doctor"))
        #expect(guide.standardOutput.contains("tccutil reset AppleEvents"))
        #expect(try rh.run(["docs", "nonsense"]).status != 0)
        #expect(try rh.run(["docs", "troubleshoot"]).standardError.contains("Did you mean \"troubleshooting\"?"))
    }

    @Test func probeLaunchRefusesAnUnknownTerminal() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let result = try rh.run(["probe", "launch", "no-such-terminal"])
        #expect(result.status != 0)
        #expect(result.standardError.contains("Unknown terminal"))
    }

    @Test func aProbeRequestedByTheExtensionRunsOnceAndAnythingAfterItDoesNothing() throws {
        let rh = try RH(config: Self.ghostTerminal); defer { rh.cleanUp() }
        let marker = rh.configDirectory.appendingPathComponent(".probe")
        try "launch".write(to: marker, atomically: true, encoding: .utf8)
        // The ghost terminal is never installed, so this opens nothing and sends no Apple event.
        let first = try rh.run(["probe", "launch", "ghost", "--from-extension"])
        #expect(first.status == 1)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        let log = rh.configDirectory.appendingPathComponent("logs/rh.log")
        let logged = try String(contentsOf: log, encoding: .utf8)
        #expect(logged.contains("probe launch: "))
        let second = try rh.run(["probe", "launch", "ghost", "--from-extension"])
        #expect(second.status == 0)
        #expect(try String(contentsOf: log, encoding: .utf8) == logged)
    }

    @Test func menuJSONIsAnArrayOfNodes() throws {
        let rh = try RH(config: "[menu]\nitems = [\"copy-path\"]\n"); defer { rh.cleanUp() }
        let result = try rh.run(["menu", "--container", "/tmp", "--json"])
        let nodes = try #require(result.json as? [[String: Any]])
        #expect(nodes.count == 1)
        #expect(nodes[0]["title"] as? String == "Copy Path")
    }

    @Test func aMenuPreviewOfAPathThatIsNotThereIsRefusedLikeARun() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let result = try rh.run(["menu", "--", "/definitely/not/here"])
        #expect(result.status == 1)
        #expect(result.standardError.contains("does not exist"))
    }

    @Test func menuCanBePreviewedInAnotherLanguage() throws {
        let rh = try RH(config: "[menu]\nitems = [\"copy-path\"]\n"); defer { rh.cleanUp() }
        let text = try rh.run(["menu", "--container", "/tmp", "--language", "de"]).standardOutput
        #expect(text.contains("Pfad kopieren"))
    }

    @Test func theQuickStartIsTheFirstTopicAndTheMCPGuideNamesEveryTool() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let listing = try rh.run(["docs"]).standardOutput.split(separator: "\n").map(String.init)
        #expect(listing.first == "Topics:" && listing.dropFirst().first?.hasPrefix("  start") == true, "\(listing.prefix(3))")
        let start = try rh.run(["docs", "start"]).standardOutput
        #expect(start.contains("rh setup") && start.contains("rh doctor") && start.contains("rh menu"), Comment(rawValue: start))
        #expect(!start.contains("rh init") && !start.contains("rh install"), "the quick start names the one command: \(start)")
        let mcp = try rh.run(["docs", "mcp"])
        #expect(mcp.status == 0 && mcp.standardOutput.contains("claude mcp add right-here -- rh mcp"), Comment(rawValue: mcp.standardError))
        for tool in ["right_here_run", "right_here_docs", "right_here_bookmarks", "right_here_worktree"] {
            #expect(mcp.standardOutput.contains("`\(tool)`"), "docs mcp does not name \(tool)")
        }
        let help = try rh.run(["--help"]).standardOutput
        #expect(help.contains("rh setup") && help.contains("rh doctor") && help.contains("rh docs start"), Comment(rawValue: help))
    }

    @Test func aDoctorReportHoldsNoHomeFolderNoAccountNameAndNoTextOfTheConfig() throws {
        // The trial home stands for the person's home: the report must not show it, nor the account name the test runs under.
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        let folder = home.appendingPathComponent(".config/right-here")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "# MARKER-CONFIG-LINE-7731\n[general]\nterminal = \"terminal\"\nmenu = [oops\n".write(to: folder.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let result = try rh.run(["doctor", "--report"])
        #expect(result.status == 1, "the config row fails, and the report exits as the doctor does")
        let report = result.standardOutput
        #expect(report.hasPrefix("# Right Here bug report"), Comment(rawValue: report))
        #expect(report.contains("- Config check (`rh config validate --strict`): 1 error"), Comment(rawValue: report))
        #expect(!report.contains("MARKER-CONFIG-LINE-7731"), "the report holds a line of the config file")
        #expect(!report.contains(home.path), "the trial home is shown as ~")
        #expect(!report.contains(NSUserName()), "the account name is in the report")
        #expect(report.contains("- macOS: "), Comment(rawValue: report))
        let both = try rh.run(["doctor", "--report", "--json"])
        #expect(both.status == 64 && both.standardError.contains("cannot be combined"), Comment(rawValue: both.standardError))
    }

    @Test func docsServeTheTopics() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        #expect(try rh.run(["docs", "config"]).standardOutput.contains("general.terminal"))
        #expect(try rh.run(["docs", "actions"]).standardOutput.contains("copy-path.<style>"))
        #expect(try rh.run(["docs", "agent-setup"]).standardOutput.contains("rh doctor --json"))
        #expect(try rh.run(["docs", "nope"]).status != 0)
    }

    @Test func initWritesAConfigThatValidates() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        #expect(try rh.run(["init"]).status == 0)
        #expect(FileManager.default.fileExists(atPath: rh.configDirectory.appendingPathComponent("config.toml").path))
        #expect(try rh.run(["config", "validate"]).status == 0)
        // A second init keeps the file.
        #expect(try rh.run(["init"]).standardOutput.contains("so setup never rewrites it"))
    }

    @Test func mcpFramingSplitsOnLineFeedsOnly() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let process = Process()
        process.executableURL = rh.binary
        process.arguments = ["mcp"]
        process.environment = rh.environment()
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        let timer = rh.watchdog(process)
        defer { timer.cancel() }
        // A raw U+2028, U+2029 or U+0085 inside a JSON string is legal; Foundation's line splitting would
        // cut the request in pieces and answer with parse errors. (A raw CR or LF inside a string is not
        // legal JSON, and the transport has no way to send one.)
        let first = "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ping\",\"params\":{\"name\":\"a\u{2028}b\u{2029}c\u{85}d\"}}\n"
        let second = "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"ping\"}\r\n"
        input.fileHandleForWriting.write(Data((first + second).utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let replies = try String(decoding: data, as: UTF8.self).split(separator: "\n").map {
            try #require(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        #expect(replies.count == 2, "got \(replies)")
        #expect(Set(replies.compactMap { $0["id"] as? Int }) == [7, 8])
        #expect(replies.allSatisfy { $0["error"] == nil })
    }

    /// Feeds `input` to `rh mcp`, closes standard input, and returns every line it answered.
    private func mcpReplies(_ rh: RH, to input: Data) throws -> [[String: Any]] {
        let process = Process()
        process.executableURL = rh.binary
        process.arguments = ["mcp"]
        process.environment = rh.environment()
        let inputPipe = Pipe(), outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        try process.run()
        let timer = rh.watchdog(process)
        defer { timer.cancel() }
        // Output is read on another thread: a server that answers 3000 requests would otherwise block on a
        // full pipe while this thread is still writing.
        final class Collected: @unchecked Sendable { var data = Data() }
        let collected = Collected()
        let reader = Thread { collected.data = outputPipe.fileHandleForReading.readDataToEndOfFile() }
        reader.start()
        try inputPipe.fileHandleForWriting.write(contentsOf: input)
        try inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()
        while !reader.isFinished { usleep(10_000) }
        return try String(decoding: collected.data, as: UTF8.self).split(separator: "\n").map {
            try #require(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    @Test func mcpRefusesAnOversizedLineAndKeepsServing() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        // A request bigger than the server will buffer: it is answered once, with an error, and then ignored.
        let huge = Data(repeating: UInt8(ascii: "x"), count: 3 * 1024 * 1024)
        var input = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8) + Data("\n".utf8)
        input += huge + Data("\n".utf8)
        input += Data(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#.utf8) + Data("\n".utf8)
        let replies = try mcpReplies(rh, to: input)
        #expect(replies.count == 3, "got \(replies.count) replies")
        let errors = replies.filter { $0["error"] != nil }
        #expect(errors.count == 1)
        #expect((errors.first?["error"] as? [String: Any])?["code"] as? Int == -32600)
        #expect(Set(replies.compactMap { $0["id"] as? Int }) == [1, 2], "the requests either side of the huge line were not both answered")
    }

    @Test func aRequestAsBigAsTheBiggestHonestOneIsStillServed() throws {
        // 200 paths of 1024 characters each: the schema's own limits, about 200 KB of JSON.
        let rh = try RH(); defer { rh.cleanUp() }
        let paths = (0..<200).map { index in "\"/" + String(repeating: "a", count: 1023 - String(index).count) + String(index) + "\"" }
        let line = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"right_here_run","arguments":{"action":"reveal","dry_run":true,"paths":["# + paths.joined(separator: ",") + "]}}}\n"
        let replies = try mcpReplies(rh, to: Data(line.utf8))
        #expect(replies.count == 1)
        // It reached the tool (which then says the paths do not exist); it was not turned away as too large.
        #expect(replies.first?["error"] == nil)
        #expect(((replies.first?["result"] as? [String: Any])?["isError"] as? Bool) == true)
    }

    @Test func mcpAnswersEveryRequestOfALongPipelinedBurst() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        var input = Data()
        for id in 0..<3000 { input += Data(#"{"jsonrpc":"2.0","id":\#(id),"method":"ping"}"#.utf8) + Data("\n".utf8) }
        let replies = try mcpReplies(rh, to: input)
        #expect(replies.count == 3000)
        #expect(Set(replies.compactMap { $0["id"] as? Int }) == Set(0..<3000))
    }

    @Test func mcpFinishesQuietlyWhenItsClientHasGone() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let process = Process()
        process.executableURL = rh.binary
        process.arguments = ["mcp"]
        process.environment = rh.environment()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let timer = rh.watchdog(process)
        defer { timer.cancel() }
        // The client vanishes: nobody reads standard output any more, while standard input stays open.
        try output.fileHandleForReading.close()
        try input.fileHandleForWriting.write(contentsOf: Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8) + Data("\n".utf8))
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        let stillRunning = process.isRunning
        if stillRunning { process.terminate() }
        process.waitUntilExit()
        #expect(!stillRunning, "the server kept running with nobody to answer")
        #expect(process.terminationReason == .exit, "it died by a signal instead of finishing")
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).isEmpty, "it wrote a crash report")
        try? input.fileHandleForWriting.close()
    }

    @Test("a request nested far deeper than any honest one is refused, and the server lives on", arguments: [40, 480, 100_000])
    func mcpSurvivesDeepNesting(depth: Int) throws {
        // About 1 KB of "[" used to overflow the decoder's stack and kill the server (SIGBUS).
        let rh = try RH(); defer { rh.cleanUp() }
        let deep = String(repeating: "[", count: depth) + "1" + String(repeating: "]", count: depth)
        let input = Data(("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{\"x\":" + deep + "}}\n"
                          + "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}\n").utf8)
        let replies = try mcpReplies(rh, to: input)
        #expect(replies.count == 2, "got \(replies)")
        let refusal = replies.first { ($0["error"] as? [String: Any])?["code"] as? Int == -32600 }
        #expect(refusal != nil, "the deep request should be refused as invalid")
        #expect(replies.contains { $0["id"] as? Int == 2 && $0["result"] != nil }, "the ping after it was not answered")
    }

    @Test("a dotted key a thousand segments long is a syntax error, not a stack overflow", arguments: ["", "x = {"])
    func aLongDottedKeyIsASyntaxErrorNotACrash(prefix: String) throws {
        let key = String(repeating: "a.", count: 1_000) + "b = 1"
        let rh = try RH(config: prefix + key + (prefix.isEmpty ? "" : "}") + "\n")
        defer { rh.cleanUp() }
        let result = try rh.run(["config", "validate"])
        #expect(result.status == 1, "status \(result.status): \(result.standardError)")
        #expect(try rh.run(["actions"]).status == 0)
    }

    @Test("an empty path or an unknown menu language is refused, not guessed", arguments: [
        (["run", "copy-path.absolute", "--dry-run", ""], "empty path"),
        (["run", "copy-path.absolute", "--dry-run", "--container", ""], "empty path"),
        (["menu", "--language", "xx"], "No translation")
    ])
    func emptyPathAndUnknownLanguageAreRefused(arguments: [String], message: String) throws {
        let rh = try RH(config: "")
        defer { rh.cleanUp() }
        let result = try rh.run(arguments)
        #expect(result.status != 0, "status \(result.status)")
        #expect((result.standardOutput + result.standardError).contains(message))
    }

    @Test func aFailedRunWithJSONPrintsJSONOnStdout() throws {
        let rh = try RH(config: "")
        defer { rh.cleanUp() }
        let result = try rh.run(["run", "open.terminal", "--json", "/nonexistent-rh-test-folder"])
        #expect(result.status == 1)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any])
        #expect(object["ok"] as? Bool == false)
        #expect((object["error"] as? String)?.contains("does not exist") == true)
    }

    @Test("a config that ends inside an unterminated header is a syntax error, not a crash", arguments: ["[\"\"", "[ ''", "[[\"\"", "x = 1\n[\"\"", "[\"\".\"\""])
    func aTruncatedHeaderIsASyntaxErrorNotACrash(text: String) throws {
        let rh = try RH(config: text); defer { rh.cleanUp() }
        let result = try rh.run(["config", "validate"])
        #expect(result.status == 1, "status \(result.status): \(result.standardError)")
        #expect(try rh.run(["actions"]).status == 0)
    }

    @Test func aConfigNestedFarDeeperThanAnyRealOneIsASyntaxErrorNotACrash() throws {
        let rh = try RH(config: "x = " + String(repeating: "[", count: 5_000) + String(repeating: "]", count: 5_000) + "\n")
        defer { rh.cleanUp() }
        let result = try rh.run(["config", "validate"])
        #expect(result.status == 1, "status \(result.status): \(result.standardError)")
        #expect((result.standardOutput + result.standardError).contains("nested more than"))
        // Every other command keeps working with that config in place: defaults apply.
        #expect(try rh.run(["actions"]).status == 0)
    }

    @Test("a folder name with terminal escape sequences never reaches the screen unescaped, in any text rh prints")
    func namesAreEscapedInEveryLineRhPrints() throws {
        let rh = try RH(config: "[new_file]\nthen = \"nothing\"\n"); defer { rh.cleanUp() }
        let hostile = "dir\u{1b}]0;PWNED\u{7}\u{1b}[31mred"
        let folder = rh.configDirectory.appendingPathComponent(hostile)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let missing = rh.configDirectory.appendingPathComponent("nope\u{1b}[2J").path
        let outputs = [
            try rh.run(["run", "open.terminal@terminal", "--dry-run", "--container", folder.path]),
            try rh.run(["run", "new-file.md", "--dry-run", "--container", folder.path]),
            try rh.run(["run", "reveal", "--dry-run", missing]),
            try rh.run(["run", "reveal", "--dry-run", "--", folder.path]),
            try rh.run(["menu", "--container", folder.path]),
            try rh.run(["menu", "--", folder.path]),
            try rh.run(["run", "new-file.md", "--container", folder.path])
        ]
        for output in outputs {
            let bytes = Array((output.standardOutput + output.standardError).utf8)
            #expect(!bytes.contains(0x1b) && !bytes.contains(0x07), "raw terminal control bytes in: \(output.standardOutput.debugDescription) \(output.standardError.debugDescription)")
        }
        #expect(outputs[0].status == 0 && outputs[2].status == 1, "the commands were meant to run")
    }

    @Test("the names the config gives are escaped in every list rh prints, bidirectional controls included")
    func namesFromTheConfigNeverReachTheScreenRaw() throws {
        // The config refuses a control character in a name, but not an override such as U+202E, which makes a name read
        // backwards in a terminal: `Evil \u{202E}detseb` shows as `Evil bestedl`. The lists print what the config says.
        let config = """
        [general]
        terminal = "terminal"
        agents = ["claude", "mine"]
        [[app]]
        id = "evil"
        name = "Evil \\u202Edetseb\\u2066 end"
        bundle_id = "com.apple.finder"
        role = "editor"
        [agent.mine]
        name = "Mine \\u202Ex"
        command = "mine"
        [[new_file.template]]
        id = "t1"
        title = "Notes \\u202Eevil"
        extension = "txt"
        """
        let rh = try RH(config: config); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let controls: Set<Unicode.Scalar> = ["\u{202E}", "\u{2066}", "\u{2069}"]
        let lists = [["actions"], ["actions", "--all"], ["apps"], ["agents"], ["menu", "--container", folder.path], ["menu", "--explain", "--container", folder.path]]
        for arguments in lists {
            let result = try rh.run(arguments)
            #expect(result.status == 0, Comment(rawValue: "\(arguments): \(result.standardError)"))
            #expect(!result.standardOutput.unicodeScalars.contains { controls.contains($0) }, "rh \(arguments.joined(separator: " ")) printed a bidirectional control raw: \(result.standardOutput.debugDescription)")
        }
        #expect(try rh.run(["apps"]).standardOutput.contains("Evil \\u202edetseb\\u2066 end"))
        #expect(try rh.run(["actions"]).standardOutput.contains("New Notes \\u202eevil"))
        #expect(try rh.run(["agents"]).standardOutput.contains("Mine \\u202ex"))
        // `--json` is for programs and says what the config says, as JSON.
        #expect(try rh.run(["apps", "--json"]).json != nil)
    }

    @Test func aWorkingDirectoryThatWasDeletedIsNoTargetNotTheRelativePathDot() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let doomed = rh.configDirectory.appendingPathComponent("doomed")
        try FileManager.default.createDirectory(at: doomed, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "cd \"$1\" && rmdir \"$1\" && exec \"$2\" run agent.claude@terminal --dry-run", "sh", doomed.path, rh.binary.path]
        process.environment = rh.environment()
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let timer = rh.watchdog(process)
        defer { timer.cancel() }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) + String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 1, Comment(rawValue: text))
        #expect(!text.contains("cd . "), "it planned a cd into the relative path dot")
        #expect(text.contains("no folder"), Comment(rawValue: text))
    }

    @Test func aConfigDefinedTerminalReallyStartsACommandThroughItsTemplate() throws {
        // The "terminal" is /usr/bin/touch: no window, but the real executor runs the real argument vector.
        let config = """
        [general]
        agents = ["marker"]
        [[app]]
        id = "faketerm"
        name = "Fake"
        bundle_id = "com.apple.finder"
        role = "terminal"
        run_args = ["/usr/bin/touch", "{dir}/ran-{command}"]
        [agent.marker]
        name = "marker"
        command = "marker"
        """
        let rh = try RH(config: config); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("it's a folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let result = try rh.run(["run", "agent.marker@faketerm", "--container", folder.path])
        #expect(result.status == 0, Comment(rawValue: result.standardError))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("ran-marker").path), "the template did not run in the folder")
    }

    @Test func mcpAnswersAMalformedRequestWithoutStoppingTheOnesAfterIt() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let input = Data("{broken\n{\"jsonrpc\":\"2.0\",\"id\":true,\"method\":\"ping\"}\n5\n{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"ping\"}\n".utf8)
        let replies = try mcpReplies(rh, to: input)
        #expect(replies.count == 4)
        #expect(replies.filter { $0["result"] != nil }.count == 1)
        #expect(replies.filter { ($0["error"] as? [String: Any])?["code"] as? Int == -32700 }.count == 1)
        #expect(replies.filter { ($0["error"] as? [String: Any])?["code"] as? Int == -32600 }.count == 2, "the boolean id and the bare 5")
    }

    @Test func mcpAnswersOverStandardInput() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let process = Process()
        process.executableURL = rh.binary
        process.arguments = ["mcp"]
        process.environment = rh.environment()
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        let timer = rh.watchdog(process)
        defer { timer.cancel() }
        input.fileHandleForWriting.write(Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#.utf8) + Data("\n".utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let reply = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((reply["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18")
    }
}

@Suite("rh config sync")
struct ConfigSyncCLITests {
    /// An `rh` whose home, config included, is a folder of its own, with the config written where `rh config path` says.
    private func isolated(config: String? = nil) throws -> RH {
        let rh = try RH(trialHome: true)
        if let config {
            let file = try configFile(rh)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try config.write(to: file, atomically: true, encoding: .utf8)
        }
        return rh
    }

    /// Where `rh config path` says the config is. Tests remove it, and change its mode, so it must really be a path: an `rh`
    /// that crashed prints nothing, and an empty path is the current folder, which is the package (a test removed the
    /// whole clone under a mutation that made `rh` crash, and another left it without permissions).
    private func configFile(_ rh: RH) throws -> URL {
        let path = try rh.run(["config", "path"]).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        try #require(path.hasPrefix("/") && path.hasSuffix("/config.toml"), "rh config path printed \(path.debugDescription)")
        return URL(fileURLWithPath: path)
    }

    @Test func theDefaultFolderIsResolvedThroughTheTrialHome() throws {
        let rh = try isolated(); defer { rh.cleanUp() }
        let result = try rh.run(["config", "sync", "enable"])
        #expect(result.status == 0, "\(result.standardError)")
        let home = try #require(rh.home)
        #expect(result.standardOutput.contains(home.path + "/Library/Mobile Documents/com~apple~CloudDocs/Right Here"))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Library").path), "enable must not create the folder")
    }

    @Test func pushStatusPullRoundTrip() throws {
        let rh = try isolated(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(try rh.run(["config", "sync", "status"]).status == 1)
        #expect(try rh.run(["config", "sync", "enable", "--folder", folder.path]).status == 0)
        let before = try #require(try rh.run(["config", "sync", "status", "--json"]).json as? [String: Any])
        #expect(before["status"] as? String == "remote-missing")
        #expect(try rh.run(["config", "sync", "push"]).status == 0)
        #expect(try String(contentsOf: folder.appendingPathComponent("config.toml"), encoding: .utf8) == "[general]\nterminal = \"terminal\"\n")
        let after = try #require(try rh.run(["config", "sync", "status", "--json"]).json as? [String: Any])
        #expect(after["status"] as? String == "in-sync")
        try "[general]\nterminal = \"ghostty\"\n".write(to: folder.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        #expect((try rh.run(["config", "sync", "status", "--json"]).json as? [String: Any])?["status"] as? String == "remote-ahead")
        #expect(try rh.run(["config", "sync", "pull"]).status == 0)
        #expect(try String(contentsOf: try configFile(rh), encoding: .utf8) == "[general]\nterminal = \"ghostty\"\n")
        #expect(try rh.run(["config", "sync", "disable"]).status == 0)
        #expect(try rh.run(["config", "sync", "status"]).status == 1)
    }

    @Test func aDeletedConfigIsRestoredByAPlainPullAndTheAdviceSaysSo() throws {
        let rh = try isolated(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try rh.run(["config", "sync", "enable", "--folder", folder.path])
        #expect(try rh.run(["config", "sync", "push"]).status == 0)
        let local = try configFile(rh)
        try FileManager.default.removeItem(at: local)
        let status = try rh.run(["config", "sync", "status"])
        #expect(status.standardOutput.contains("remote-ahead") && status.standardOutput.contains("`rh config sync pull`"), "\(status.standardOutput)")
        #expect(!status.standardOutput.contains("`rh config sync push`"), "advice to push a file that is not there: \(status.standardOutput)")
        #expect(try rh.run(["config", "sync", "pull"]).status == 0)
        #expect(try String(contentsOf: local, encoding: .utf8) == "[general]\nterminal = \"terminal\"\n")
    }

    @Test func pullRefusesALocalEditUnlessForced() throws {
        let rh = try isolated(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try rh.run(["config", "sync", "enable", "--folder", folder.path])
        _ = try rh.run(["config", "sync", "push"])
        let local = try configFile(rh)
        try "[general]\nterminal = \"ghostty\"\n".write(to: local, atomically: true, encoding: .utf8)
        try "[general]\neditor = \"vscode\"\n".write(to: folder.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let refused = try rh.run(["config", "sync", "pull"])
        #expect(refused.status == 1)
        #expect(refused.standardError.contains("--force"))
        #expect(try String(contentsOf: local, encoding: .utf8) == "[general]\nterminal = \"ghostty\"\n")
        #expect(try rh.run(["config", "sync", "pull", "--force"]).status == 0)
        #expect(try String(contentsOf: local, encoding: .utf8) == "[general]\neditor = \"vscode\"\n")
        let saved = try FileManager.default.contentsOfDirectory(atPath: local.deletingLastPathComponent().path).filter { $0.hasPrefix("config.toml.bak-") }
        #expect(saved.count == 1)
    }

    @Test func aPullThatWouldAddProgramsIsRefusedUntilTheyAreAllowed() throws {
        let original = "[general]\nterminal = \"terminal\"\n"
        let rh = try isolated(config: original); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try rh.run(["config", "sync", "enable", "--folder", folder.path])
        #expect(try rh.run(["config", "sync", "push"]).status == 0)
        // What someone with write access to the folder can leave there: the built-in terminal, redefined to run a program.
        let planted = """
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
        try planted.write(to: folder.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let local = try configFile(rh)
        let status = try rh.run(["config", "sync", "status"])
        #expect(status.standardOutput.contains("/usr/bin/id") && status.standardOutput.contains("--allow-commands"), "\(status.standardOutput)")
        let pending = (try rh.run(["config", "sync", "status", "--json"]).json as? [String: Any])?["pendingLaunchCommands"] as? [String]
        #expect(pending?.contains { $0.contains("run_args") && $0.contains("/bin/sh") } == true, "\(String(describing: pending))")

        let refused = try rh.run(["config", "sync", "pull"])
        #expect(refused.status == 1)
        #expect(refused.standardError.contains("--allow-commands") && refused.standardError.contains("/usr/bin/id"), "\(refused.standardError)")
        #expect(try String(contentsOf: local, encoding: .utf8) == original)
        // --force is about this Mac's own edits, not about programs.
        try "[general]\nterminal = \"ghostty\"\n".write(to: local, atomically: true, encoding: .utf8)
        let forced = try rh.run(["config", "sync", "pull", "--force"])
        #expect(forced.status == 1 && forced.standardError.contains("--allow-commands"), "\(forced.standardError)")
        #expect(try String(contentsOf: local, encoding: .utf8) == "[general]\nterminal = \"ghostty\"\n")

        let allowed = try rh.run(["config", "sync", "pull", "--force", "--allow-commands"])
        #expect(allowed.status == 0, "\(allowed.standardError)")
        #expect(try String(contentsOf: local, encoding: .utf8) == planted)
        #expect(try rh.run(["config", "sync", "pull", "--help"]).standardOutput.contains("--allow-commands"))
    }

    @Test func textFromTheConfigIsNeverPrintedRaw() throws {
        // Keys and values a config can carry: terminal escape sequences, a bell, a C1 control, a right-to-left override.
        let hostile = """
        "k\\u001b]0;pwned\\u0007" = 1
        [general]
        terminal = "x\\u001b[2J\\u202Egnp"
        [menu]
        items = ["agent.\\u009b31m"]
        """
        func acts(_ text: String) -> Bool {
            text.unicodeScalars.contains { $0 != "\n" && ($0.properties.generalCategory == .control || $0 == "\u{202E}") }
        }
        let rh = try isolated(config: hostile); defer { rh.cleanUp() }
        let validate = try rh.run(["config", "validate"])
        let json = try rh.run(["config", "validate", "--json"])
        // `run` and `menu` report config problems on standard error before they do anything.
        let run = try rh.run(["run", "--dry-run", "copy-path.name", rh.configDirectory.path])
        let menu = try rh.run(["menu", "--container", rh.configDirectory.path])
        for (name, text) in [("validate", validate.standardOutput), ("validate --json", json.standardOutput), ("run", run.standardError + run.standardOutput), ("menu", menu.standardError)] {
            #expect(!acts(text), "\(name) printed a character a terminal acts on: \(text.debugDescription)")
            #expect(text.contains("\\u001b") || text.contains("\\\\u001b"), "\(name) did not show the escaped key: \(text.debugDescription)")
        }
    }

    @Test func aHostileKeyInTheFolderConfigIsNeverPrintedRawByPull() throws {
        let rh = try isolated(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try rh.run(["config", "sync", "enable", "--folder", folder.path])
        _ = try rh.run(["config", "sync", "push"])
        try "[general]\nterminal = \"terminal\"\n\"token\\u001b]52;c;ZWNobyBwd25lZA==\\u0007\" = \"x\"\n".write(to: folder.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let result = try rh.run(["config", "sync", "pull"])
        #expect(result.status == 1)
        #expect(!result.standardError.unicodeScalars.contains { $0 != "\n" && $0.properties.generalCategory == .control }, "\(result.standardError.debugDescription)")
        #expect(result.standardError.contains(#"token\u001b]52"#), "\(result.standardError)")
        #expect(!result.standardError.contains(".."), "\(result.standardError)")
    }

    @Test func enablingOnAMachineWithoutAConfigSaysWhatTheFolderWouldStart() throws {
        let rh = try isolated(); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "[agent.mine]\nname = \"Mine\"\ncommand = \"mine --yes\"\n".write(to: folder.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let result = try rh.run(["config", "sync", "enable", "--folder", folder.path])
        #expect(result.status == 0)
        #expect(result.standardOutput.contains("mine --yes") && result.standardOutput.contains("--allow-commands"), "\(result.standardOutput)")
        #expect(!FileManager.default.fileExists(atPath: try configFile(rh).path))
    }

    @Test func aConfigWithASecretLookingKeyIsNotPushed() throws {
        let rh = try isolated(config: "[agent.mine]\nname = \"M\"\ncommand = \"m\"\napi_key = \"x\"\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try rh.run(["config", "sync", "enable", "--folder", folder.path])
        let result = try rh.run(["config", "sync", "push", "--force"])
        #expect(result.status == 1)
        #expect(result.standardError.contains("secret"))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("config.toml").path))
    }

    @Test func anOverlayIsReadByValidateAndNamedInProblems() throws {
        let rh = try isolated(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        let overlay = try configFile(rh).deletingLastPathComponent().appendingPathComponent("config.local.toml")
        try "[general]\ntermnial = \"x\"\n".write(to: overlay, atomically: true, encoding: .utf8)
        let result = try rh.run(["config", "validate"])
        #expect(result.standardOutput.contains("config.local.toml"))
        let report = try #require(try rh.run(["config", "validate", "--json"]).json as? [String: Any])
        #expect(report["localExists"] as? Bool == true)
        #expect((report["diagnostics"] as? [[String: Any]])?.first?["file"] as? String == "config.local.toml")
    }

    @Test func aCopyPastTheSizeLimitIsReportedAndNeitherReadNorReplaced() throws {
        let rh = try isolated(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let huge = "[agent.mine]\nname = \"Mine\"\ncommand = \"mine --yes\"\n# " + String(repeating: "x", count: ConfigParser.maxBytes) + "\n"
        try huge.write(to: folder.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let enable = try rh.run(["config", "sync", "enable", "--folder", folder.path])
        #expect(enable.status == 0, "\(enable.standardError)")
        #expect(enable.standardOutput.contains("remote-evicted") && enable.standardOutput.contains("past the 1024 KB a config may have"), "\(enable.standardOutput)")
        #expect(!enable.standardOutput.contains("mine --yes"), "the copy was parsed: \(enable.standardOutput)")
        let json = try #require(try rh.run(["config", "sync", "status", "--json"]).json as? [String: Any])
        #expect(json["remoteSHA256"] == nil && (json["pendingLaunchCommands"] as? [String])?.isEmpty == true, "\(json)")
        #expect((json["remoteProblems"] as? [String])?.count == 1 && (json["remoteProblems"] as? [String])?.first?.contains("the limit is 1024 KB") == true, "\(json)")
        #expect((json["localProblems"] as? [String])?.isEmpty == true, "\(json)")
        for arguments in [["pull", "--force", "--allow-commands"], ["push", "--force"]] {
            let refused = try rh.run(["config", "sync"] + arguments)
            #expect(refused.status == 1 && refused.standardError.contains("is never replaced"), "\(arguments): \(refused.standardError)")
        }
        #expect(try String(contentsOf: folder.appendingPathComponent("config.toml"), encoding: .utf8) == huge)
        #expect(try String(contentsOf: try configFile(rh), encoding: .utf8) == "[general]\nterminal = \"terminal\"\n")
    }

    @Test func aNameWithAnEscapeSequenceIsAnErrorForValidateAndStopsAPull() throws {
        // What a config from the sync folder can carry in an app's name: an OSC 52 clipboard write and a bell.
        let hostile = "[[app]]\nid = \"evil\"\nname = \"Evil\\u001b]52;c;aGk=\\u0007\"\nbundle_id = \"com.apple.TextEdit\"\nrole = \"editor\"\n"
        let rh = try isolated(config: hostile); defer { rh.cleanUp() }
        let validate = try rh.run(["config", "validate"])
        #expect(validate.status == 1, "\(validate.standardOutput)")
        #expect(validate.standardOutput.contains("app.1.name") && validate.standardOutput.contains("control character"), "\(validate.standardOutput)")
        #expect(!validate.standardOutput.unicodeScalars.contains { $0 == "\u{1B}" || $0 == "\u{07}" }, "\(validate.standardOutput.debugDescription)")
        let json = try #require(try rh.run(["config", "validate", "--json"]).json as? [String: Any])
        #expect(json["ok"] as? Bool == false && !((json["diagnostics"] as? [[String: Any]]) ?? []).isEmpty)
        // The same config in the sync folder is refused by `pull`, with or without the flags.
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try hostile.write(to: folder.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: try configFile(rh))
        _ = try rh.run(["config", "sync", "enable", "--folder", folder.path])
        let pull = try rh.run(["config", "sync", "pull", "--force", "--allow-commands"])
        #expect(pull.status == 1 && pull.standardError.contains("control character"), "\(pull.standardError)")
        #expect(!FileManager.default.fileExists(atPath: try configFile(rh).path))
    }

    @Test func aConfigWithoutPermissionIsAnErrorEverywhereAndNotAMissingFile() throws {
        let rh = try isolated(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        let file = try configFile(rh)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        try #require(!FileManager.default.isReadableFile(atPath: file.path), "running as a user that ignores permissions")
        let validate = try rh.run(["config", "validate"])
        #expect(validate.status == 1 && validate.standardOutput.contains("cannot read \(file.path): Permission denied"), "\(validate.standardOutput)")
        #expect(!validate.standardOutput.contains("No config file"))
        let json = try #require(try rh.run(["config", "validate", "--json"]).json as? [String: Any])
        #expect(json["exists"] as? Bool == true && json["ok"] as? Bool == false, "\(json)")
        let doctor = try rh.run(["doctor", "--json"])
        let checks = try #require((doctor.json as? [String: Any])?["checks"] as? [[String: Any]])
        let config = try #require(checks.first { $0["id"] as? String == "config" })
        #expect(config["status"] as? String == "fail" && ((config["detail"] as? [String: Any])?["text"] as? String)?.contains("Permission denied") == true, "\(config)")
        let initialized = try rh.run(["init"])
        #expect(initialized.standardOutput.contains("already exists but was not read") && initialized.standardOutput.contains("Permission denied"), "\(initialized.standardOutput)")
        #expect(!initialized.standardOutput.contains("Use --force"), "--force cannot save a file it cannot read: \(initialized.standardOutput)")
    }

    @Test func aPresetLeftOutBecauseItsAgentIsDisabledHereIsANoteThatStrictAndMenuIgnore() throws {
        let shared = "[general]\nagents = [\"claude\", \"codex\"]\n[[preset]]\nid = \"security-review\"\ntitle = \"Security review\"\nagent = \"codex\"\nprompt = \"Review {files} for security problems.\"\n"
        let rh = try isolated(config: shared); defer { rh.cleanUp() }
        let overlay = try configFile(rh).deletingLastPathComponent().appendingPathComponent("config.local.toml")
        try "disabled = [\"codex\"]\n".write(to: overlay, atomically: true, encoding: .utf8)
        let strict = try rh.run(["config", "validate", "--strict"])
        #expect(strict.status == 0, "a note failed --strict: \(strict.standardOutput)")
        let lines = strict.standardOutput.split(separator: "\n").map(String.init)
        #expect(lines.count == 2 && lines[0].hasPrefix("ok: ") && lines[1].hasPrefix("note: config.local.toml:1 [disabled]: the preset \"security-review\" is not offered on this machine"), "\(lines)")
        let json = try #require(try rh.run(["config", "validate", "--json"]).json as? [String: Any])
        #expect(json["clean"] as? Bool == true && json["ok"] as? Bool == true && (json["diagnostics"] as? [Any])?.isEmpty == true, "\(json)")
        let notes = try #require(json["notes"] as? [[String: Any]])
        #expect(notes.count == 1 && notes.first?["severity"] as? String == "note" && notes.first?["file"] as? String == "config.local.toml", "\(notes)")
        // `rh menu` reports config problems on standard error every time; a note is no problem.
        let menu = try rh.run(["menu", "--container", rh.configDirectory.path])
        #expect(menu.standardError.isEmpty, "\(menu.standardError)")
        #expect(!menu.standardOutput.contains("security-review"))
    }

    @Test func anErrorTheOverlayMasksIsReportedByValidateAndRefusedByPush() throws {
        // The usability test's case: the shared file has an unknown style, the overlay replaces the list. As it applies here
        // all is well; other Macs read the shared file.
        let rh = try isolated(config: "[copy_path]\nstyles = [\"absolute\", \"relative\"]\n"); defer { rh.cleanUp() }
        let overlay = try configFile(rh).deletingLastPathComponent().appendingPathComponent("config.local.toml")
        try "[copy_path]\nstyles = [\"tilde\"]\n".write(to: overlay, atomically: true, encoding: .utf8)
        let validate = try rh.run(["config", "validate"])
        #expect(validate.status == 1, "validate said ok: \(validate.standardOutput)")
        #expect(validate.standardOutput.hasPrefix("error: config.toml:2 [copy_path.styles]: unknown style \"relative\""), "\(validate.standardOutput)")
        #expect(validate.standardOutput.contains("config.local.toml hides it on this Mac"), "\(validate.standardOutput)")
        // `menu` and `run` load the config as it applies here, and say nothing.
        #expect(try rh.run(["menu", "--container", rh.configDirectory.path]).standardError.isEmpty)
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try rh.run(["config", "sync", "enable", "--folder", folder.path])
        let push = try rh.run(["config", "sync", "push"])
        #expect(push.status == 1 && push.standardError.contains("unknown style \"relative\""), "\(push.standardError)")
    }

    @Test func aKeyNamedLikeACredentialIsAnErrorInValidateAsPushRefusesIt() throws {
        let rh = try isolated(config: "[agent.mine]\nname = \"M\"\ncommand = \"m\"\napi_key = \"x\"\n[general]\nagents = [\"mine\"]\n"); defer { rh.cleanUp() }
        let result = try rh.run(["config", "validate"])
        #expect(result.status == 1 && result.standardOutput.hasPrefix("error: config.toml:4 [agent.mine.api_key]: unknown key; named like a credential"), "\(result.standardOutput)")
        // push refuses the same file for the same key.
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try rh.run(["config", "sync", "enable", "--folder", folder.path])
        let push = try rh.run(["config", "sync", "push", "--force"])
        #expect(push.status == 1 && push.standardError.contains("agent.mine.api_key"), "\(push.standardError)")
    }

    @Test func anEmptyFolderIsRefusedAndNothingIsEnabled() throws {
        let rh = try isolated(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        // What `--folder "$UNSET_VARIABLE"` passes. It used to make the current folder the sync folder.
        let result = try rh.run(["config", "sync", "enable", "--folder", ""])
        #expect(result.status == 1 && result.standardError.contains("The folder is empty (is a shell variable unset?)"), "\(result.standardError)")
        #expect(try rh.run(["config", "sync", "status"]).status == 1, "sync was enabled")
        #expect(!FileManager.default.fileExists(atPath: try configFile(rh).deletingLastPathComponent().appendingPathComponent("sync.toml").path))
    }

    @Test func pushSaysItCreatesOnlyTheLastFolderAndHowToMakeTheParent() throws {
        let rh = try isolated(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        let home = try #require(rh.home).path
        let enable = try rh.run(["config", "sync", "enable", "--folder", "~/Sync/rh"])
        #expect(enable.status == 0 && enable.standardOutput.contains("Next: make the parent folder first, `mkdir -p \(home)/Sync`") && !enable.standardOutput.contains("Next: `rh config sync push`"), "\(enable.standardOutput)")
        let push = try rh.run(["config", "sync", "push"])
        #expect(push.status == 1, "\(push.standardError)")
        #expect(push.standardError.contains("creates the last folder of the path only") && push.standardError.contains("`mkdir -p \(home)/Sync`"), "\(push.standardError)")
        try FileManager.default.createDirectory(atPath: home + "/Sync", withIntermediateDirectories: true)
        #expect(try rh.run(["config", "sync", "status"]).standardOutput.contains("Next: `rh config sync push`."))
        #expect(try rh.run(["config", "sync", "push"]).standardOutput.hasPrefix("Created \(home)/Sync/rh and pushed"))
        for command in [["config", "sync", "enable", "--help"], ["config", "sync", "push", "--help"], ["config", "sync", "--help"]] {
            let help = try rh.run(command).standardOutput.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "  ", with: " ")
            #expect(help.contains("last folder of the"), "\(command.joined(separator: " ")): \(help)")
        }
    }

    @Test func aFolderPrintsAsItWasTyped() throws {
        let rh = try isolated(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The same folder spelled with its /private prefix: it used to come back as /var/... or /tmp/....
        let real = try #require(realpath(folder.path, nil).map { String(cString: $0) })
        try #require(real.hasPrefix("/private/"), "the temporary folder is not under /private here: \(real)")
        let enable = try rh.run(["config", "sync", "enable", "--folder", real])
        #expect(enable.standardOutput.hasPrefix("Sync folder: \(real)\n"), "\(enable.standardOutput)")
        #expect(try rh.run(["config", "sync", "status"]).standardOutput.hasPrefix("Sync folder: \(real)\n"))
        #expect(try rh.run(["config", "sync", "push"]).standardOutput.contains("to \(real)/config.toml."))
    }

    @Test func statusAdvisesNothingThatPushOrPullWouldRefuse() throws {
        let good = "[general]\nagents = [\"mine\"]\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine --yes\"\n"
        let rh = try isolated(config: good); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("synced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try rh.run(["config", "sync", "enable", "--folder", folder.path])
        #expect(try rh.run(["config", "sync", "push"]).status == 0)
        let local = try configFile(rh)

        // A syntax error: push would refuse, and Right Here runs with its defaults, so the folder's own command is new to it.
        try ("[general\n" + good).write(to: local, atomically: true, encoding: .utf8)
        var status = try rh.run(["config", "sync", "status"]).standardOutput
        #expect(status.contains("This machine's config would be refused by `push`: the config is not valid: error: config.toml:1: TOML syntax error: table header not closed"), "\(status)")
        #expect(!status.contains("Next: `rh config sync push`"), "advice to push what push refuses: \(status)")
        #expect(status.contains("Next: fix this machine's config first"), "\(status)")
        #expect(status.contains("cannot be read as it is, so Right Here runs with its defaults") && !status.contains("adds or changes what Right Here starts"), "\(status)")
        #expect(status.contains("[agent.mine] command = \"mine --yes\""), "the gate's list is unchanged: \(status)")

        // A key named like a credential: refused by push, and the config itself reads fine.
        try (good + "api_key = \"x\"\n").write(to: local, atomically: true, encoding: .utf8)
        status = try rh.run(["config", "sync", "status"]).standardOutput
        #expect(status.contains("would be refused by `push`") && status.contains("agent.mine.api_key"), "\(status)")
        #expect(!status.contains("Next: `rh config sync push`") && status.contains("Next: fix this machine's config first"), "\(status)")
        #expect(!status.contains("runs with its defaults"), "\(status)")

        // The folder's copy is the broken one and this Mac has not changed: pull would refuse it.
        try good.write(to: local, atomically: true, encoding: .utf8)
        try "[general\n".write(to: folder.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        status = try rh.run(["config", "sync", "status"]).standardOutput
        #expect(status.contains("remote-ahead") && status.contains("The folder's copy would be refused by `pull`"), "\(status)")
        #expect(!status.contains("Next: `rh config sync pull`") && status.contains("Next: fix the folder's copy first"), "\(status)")
        #expect(try rh.run(["config", "sync", "pull"]).status == 1)

        // A config that cannot be read is never written over, `--force` included, so `pull --force` is not the advice either.
        try good.write(to: local, atomically: true, encoding: .utf8)
        try "[general]\nterminal = \"terminal\"\n".write(to: folder.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: local.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: local.path) }
        try #require(!FileManager.default.isReadableFile(atPath: local.path), "running as a user that ignores permissions")
        status = try rh.run(["config", "sync", "status"]).standardOutput
        #expect(status.contains("This machine's config would be refused by `push`: the file cannot be read (Permission denied)"), "\(status)")
        #expect(status.contains("Next: this machine's config was not read") && !status.contains("--force"), "\(status)")
        let forced = try rh.run(["config", "sync", "pull", "--force"])
        #expect(forced.status == 1 && forced.standardError.contains("can neither compare it"), "\(forced.standardError)")
    }

    @Test func showPrintsEveryFileThatMakesUpTheConfigUnderAHeaderAndPathListsThem() throws {
        let shared = "# shared\n[general]\nterminal = \"ghostty\"\n"
        let rh = try isolated(config: shared); defer { rh.cleanUp() }
        let base = try configFile(rh)
        let overlay = base.deletingLastPathComponent().appendingPathComponent("config.local.toml")
        // One file: a header naming it, then its text as it is.
        let one = try rh.run(["config", "show"])
        #expect(one.status == 0 && one.standardOutput == "==> \(base.path) <==\n# shared\n[general]\nterminal = \"ghostty\"\n", "\(one.standardOutput.debugDescription)")
        #expect(try rh.run(["config", "path", "--all"]).standardOutput == base.path + "\n")
        #expect(try rh.run(["config", "path"]).standardOutput == base.path + "\n")
        // Both: in the order they are read, each under its own header, and nothing merged.
        try "# this machine\n[general]\nterminal = \"terminal\"\ndisabled_here = true\n".write(to: overlay, atomically: true, encoding: .utf8)
        let both = try rh.run(["config", "show"])
        #expect(both.standardOutput == """
        ==> \(base.path) <==
        # shared
        [general]
        terminal = "ghostty"

        ==> \(overlay.path) <==
        # this machine
        [general]
        terminal = "terminal"
        disabled_here = true

        """, "\(both.standardOutput)")
        #expect(both.standardOutput.components(separatedBy: "terminal = ").count == 3, "a merged text would have one terminal")
        #expect(try rh.run(["config", "path", "--all"]).standardOutput == base.path + "\n" + overlay.path + "\n")
        #expect(try rh.run(["config", "path"]).standardOutput == base.path + "\n", "without --all, the shared file's path only")
        // An overlay alone is shown too; nothing at all is the old error.
        try FileManager.default.removeItem(at: base)
        #expect(try rh.run(["config", "show"]).standardOutput.hasPrefix("==> \(overlay.path) <==\n"))
        try FileManager.default.removeItem(at: overlay)
        let none = try rh.run(["config", "show"])
        #expect(none.status == 1 && none.standardError.contains("No config file yet at \(base.path)"), "\(none.standardError)")
        #expect(try rh.run(["config", "path", "--all"]).standardOutput == base.path + "\n")
        // The docs say so.
        let docs = try rh.run(["docs", "config"]).standardOutput
        #expect(docs.contains("rh config show") && docs.contains("rh config path --all") && docs.contains("no merged text"), "\(docs.prefix(600))")
    }

    @Test func showSaysWhyAFileCannotBeShown() throws {
        let rh = try isolated(config: "[general]\nterminal = \"terminal\"\n"); defer { rh.cleanUp() }
        let file = try configFile(rh)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        try #require(!FileManager.default.isReadableFile(atPath: file.path), "running as a user that ignores permissions")
        let result = try rh.run(["config", "show"])
        #expect(result.status == 1 && result.standardError.contains("Cannot show \(file.path): cannot read \(file.path): Permission denied"), "\(result.standardError)")
    }

    @Test func syncIsListedInHelp() throws {
        let rh = try isolated(); defer { rh.cleanUp() }
        let text = try rh.run(["config", "--help"]).standardOutput
        #expect(text.contains("sync"))
        let sync = try rh.run(["config", "sync", "--help"]).standardOutput
        for word in ["enable", "status", "pull", "push", "disable"] { #expect(sync.contains(word)) }
    }
}

@Suite("rh setup")
struct SetupCommandTests {
    private func steps(_ output: RH.Output) throws -> [String: String] {
        let report = try #require(output.json as? [String: Any], "not one JSON document: \(output.standardOutput.prefix(200))")
        let steps = try #require(report["steps"] as? [[String: Any]])
        return Dictionary(uniqueKeysWithValues: steps.compactMap { step in
            (step["id"] as? String).flatMap { id in (step["outcome"] as? String).map { (id, $0) } }
        })
    }

    @Test func aFirstRunMakesEveryPieceUnderTheTrialHomeAndASecondRunChangesNothing() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let first = try rh.run(["setup", "--json"])
        #expect(first.status == 0, "\(first.standardError)")
        #expect(try steps(first) == ["config": "created", "runnerScript": "created", "cliLink": "created", "services": "created", "finderExtension": "skipped"])
        let second = try rh.run(["setup", "--json"])
        #expect(second.status == 0, "\(second.standardError)")
        #expect(try steps(second) == ["config": "unchanged", "runnerScript": "unchanged", "cliLink": "unchanged", "services": "unchanged", "finderExtension": "skipped"])
    }

    @Test func theTextSaysWhatWasDoneAndWhatToRunNext() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let result = try rh.run(["setup"])
        #expect(result.status == 0, "\(result.standardError)")
        let lines = result.standardOutput.split(separator: "\n").map(String.init)
        #expect(lines.first == "Right Here setup")
        #expect(lines.contains { $0.hasPrefix("  Config file: created (") })
        #expect(lines.contains { $0.hasPrefix("  Quick Actions: created (") })
        #expect(lines.contains { $0.hasPrefix("  Finder extension: skipped (RH_HOME is set") })
        #expect(lines.contains("  rh menu --container ~"))
        #expect(lines.contains { $0.hasPrefix("note: RH_HOME is set, so this is a trial") })
    }

    @Test func whatThePersonSaysIsWrittenToTheNewConfigAndItValidatesClean() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let result = try rh.run(["setup", "--terminal", "terminal", "--editor", "zed", "--agents", "claude,codex"])
        #expect(result.status == 0, "\(result.standardError)")
        let shown = try rh.run(["config", "show"]).standardOutput
        #expect(shown.contains("terminal = \"terminal\"") && shown.contains("editor = \"zed\"") && shown.contains("agents = [\"claude\", \"codex\"]"), "\(shown)")
        #expect(try rh.run(["config", "validate", "--strict"]).status == 0)
        #expect(result.standardOutput.contains("terminal: Terminal (terminal, you chose it)"))
    }

    @Test func noAgentsIsSaidWithNone() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        #expect(try rh.run(["setup", "--agents", "none"]).status == 0)
        let agents = try #require(try rh.run(["agents", "--json"]).json as? [[String: Any]])
        #expect(agents.allSatisfy { $0["enabled"] as? Bool == false })
    }

    @Test func aMisspeltChoiceIsRefusedWithTheClosestIdAndNothingIsWritten() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        let result = try rh.run(["setup", "--terminal", "ghosty"])
        #expect(result.status == 64, "status \(result.status)")
        #expect(result.standardError.contains("Unknown terminal \"ghosty\" (did you mean \"ghostty\"?)"), "\(result.standardError)")
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".config/right-here").path))
        #expect(try rh.run(["setup", "--editor", "ghostty"]).standardError.contains("is a terminal, not an editor"))
        #expect(try rh.run(["setup", "--agents", "claude,codx"]).standardError.contains("did you mean \"codex\"?"))
    }

    private static let mine = "# My notes.\n[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"

    @Test func anExistingConfigIsKeptByteForByteAndTheEditToMakeIsPrinted() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        let file = home.appendingPathComponent(".config/right-here/config.toml")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.mine.write(to: file, atomically: true, encoding: .utf8)
        let result = try rh.run(["setup", "--agents", "claude,codex"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.mine, "setup rewrote a config that was there")
        #expect(result.standardOutput.contains("In config.toml on line 4, change agents = [\"claude\"] to agents = [\"claude\", \"codex\"]."), "\(result.standardOutput)")
        let json = try #require(try rh.run(["setup", "--json", "--agents", "claude,codex"]).json as? [String: Any])
        let edits = try #require(json["configEdits"] as? [[String: Any]])
        #expect(edits.count == 1 && edits.first?["line"] as? Int == 4 && edits.first?["file"] as? String == "config.toml")
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.mine)
    }

    @Test func aDryRunShowsThePlanAndWritesNothing() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        let result = try rh.run(["setup", "--dry-run", "--terminal", "terminal"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(result.standardOutput.hasPrefix("Right Here setup (a dry run: nothing was changed)\n"), "\(result.standardOutput)")
        #expect(result.standardOutput.contains("Config file: would be created"))
        #expect(result.standardOutput.contains("rh setup --terminal terminal"))
        let written = try FileManager.default.contentsOfDirectory(atPath: home.path)
        #expect(written.isEmpty, "a dry run wrote \(written)")
    }

    @Test func aStepThatFailsIsReportedInTheJSONAndTheStatusIsOne() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
        try "mine".write(to: home.appendingPathComponent(".local/bin/rh"), atomically: true, encoding: .utf8)
        let result = try rh.run(["setup", "--json"])
        #expect(result.status == 1)
        let report = try #require(result.json as? [String: Any])
        #expect(report["ok"] as? Bool == false)
        #expect(try steps(result)["cliLink"] == "failed")
        #expect(try steps(result)["config"] == "created")
    }

    @Test func installNamesAPieceAndSendsEveryoneElseToSetup() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let bare = try rh.run(["install"])
        #expect(bare.status != 0)
        #expect(bare.standardError.contains("Name what to install") && bare.standardError.contains("`rh setup`"), "\(bare.standardError)")
    }

    @Test func installDoesOnlyThePieceItWasToldTo() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        let result = try rh.run(["install", "--scripts"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(result.standardOutput.hasPrefix("  Runner script: created ("), "\(result.standardOutput)")
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Scripts/com.boyugou.righthere.FinderExtension/rh-run").path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".config").path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Services").path))
    }

    @Test func theConfigCommandsSendSomeoneWithoutAConfigToSetup() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        #expect(try rh.run(["config", "show"]).standardError.contains("Run `rh setup` to create one."))
    }
}
