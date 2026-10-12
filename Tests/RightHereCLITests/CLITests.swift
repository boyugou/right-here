import Foundation
import Testing

/// Runs the built `rh` with a throwaway config directory and its own HOME-independent paths.
private struct RH {
    let configDirectory: URL
    let binary: URL

    init(config: String? = nil) throws {
        configDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("rh-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        if let config { try config.write(to: configDirectory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8) }
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
        environment["RH_CONFIG_DIR"] = configDirectory.path
        environment["RH_LOG_DIR"] = configDirectory.appendingPathComponent("logs").path
        environment.removeValue(forKey: "RH_CONFIG")
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
        let result = try rh.run(["run", "copy-path.name", "--dry-run", "--json", "/tmp/a file.txt"])
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
        let result = try rh.run(["run", "open.terminal", "--container", script.path, "--dry-run", "--json"])
        if result.status == 0 {
            let steps = try #require((result.json as? [String: Any])?["steps"] as? [[String: Any]])
            let targets = steps.flatMap { ($0["targets"] as? [String]) ?? [] }
            #expect(!targets.contains { $0.hasSuffix("evil.command") })
        }
        #expect(!FileManager.default.fileExists(atPath: "/tmp/rh-should-not-run"))
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
        #expect(agent.standardOutput.contains("arguments: \"/tmp\", \"codex\""))
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
