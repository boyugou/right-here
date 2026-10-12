import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("RHPaths")
struct RHPathsTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test func defaultsToDotConfig() {
        let paths = RHPaths(environment: [:], home: home)
        #expect(paths.configFile.path == "/Users/tester/.config/right-here/config.toml")
    }

    @Test func xdgConfigHome() {
        let paths = RHPaths(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"], home: home)
        #expect(paths.configFile.path == "/tmp/xdg/right-here/config.toml")
    }

    @Test func configDirOverridesXdg() {
        let paths = RHPaths(environment: ["RH_CONFIG_DIR": "/tmp/rh", "XDG_CONFIG_HOME": "/tmp/xdg"], home: home)
        #expect(paths.configFile.path == "/tmp/rh/config.toml")
    }

    @Test func configFileOverridesEverything() {
        let paths = RHPaths(environment: ["RH_CONFIG": "/tmp/custom.toml", "RH_CONFIG_DIR": "/tmp/rh"], home: home)
        #expect(paths.configFile.path == "/tmp/custom.toml")
        #expect(paths.configDirectory.path == "/tmp")
    }

    @Test func logDirectoryDefaultsToLibraryLogsAndCanBeOverridden() {
        #expect(RHPaths(environment: [:], home: home).logFile.path == "/Users/tester/Library/Logs/right-here/rh.log")
        #expect(RHPaths(environment: ["RH_LOG_DIR": "/tmp/logs"], home: home).logFile.path == "/tmp/logs/rh.log")
    }

    @Test func emptyOverridesAreIgnored() {
        let paths = RHPaths(environment: ["RH_CONFIG": "", "RH_CONFIG_DIR": ""], home: home)
        #expect(paths.configFile.path == "/Users/tester/.config/right-here/config.toml")
    }
}

@Suite("ConfigStore")
struct ConfigStoreTests {
    private func paths(in directory: URL) -> RHPaths {
        RHPaths(environment: ["RH_CONFIG_DIR": directory.path], home: URL(fileURLWithPath: "/Users/tester"))
    }

    @Test func missingFileMeansDefaults() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = ConfigStore.load(paths: paths(in: directory))
        #expect(!loaded.fileExists)
        #expect(loaded.config == .default)
        #expect(loaded.result.diagnostics.isEmpty)
    }

    @Test func readsAFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try "[general]\nterminal = \"terminal\"\n".write(to: directory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let loaded = ConfigStore.load(paths: paths(in: directory))
        #expect(loaded.fileExists)
        #expect(loaded.config.terminal == "terminal")
    }

    @Test func invalidUTF8IsReported() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([0xFF, 0xFE, 0x00]).write(to: directory.appendingPathComponent("config.toml"))
        let loaded = ConfigStore.load(paths: paths(in: directory))
        #expect(loaded.result.hasErrors)
    }

    @Test func aByteOrderMarkAtTheStartOfTheFileIsIgnored() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        try ("\u{FEFF}[general]\nterminal = \"terminal\"\n").write(to: target.configFile, atomically: true, encoding: .utf8)
        let loaded = ConfigStore.load(paths: target)
        #expect(loaded.result.diagnostics.isEmpty)
        #expect(loaded.config.terminal == "terminal")
    }

    @Test func initializeWritesOnceAndDoesNotOverwrite() throws {
        let directory = try makeTemporaryDirectory().appendingPathComponent("nested")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let target = paths(in: directory)
        #expect(try ConfigStore.initialize(paths: target, detected: DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude"])) == .created)
        let first = try String(contentsOf: target.configFile, encoding: .utf8)
        #expect(try ConfigStore.initialize(paths: target, detected: DetectedEnvironment()) == .kept)
        #expect(try String(contentsOf: target.configFile, encoding: .utf8) == first)
    }

    @Test func forcingReplacesTheFileAfterSavingACopy() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        try "# my hand-made settings\n".write(to: target.configFile, atomically: true, encoding: .utf8)
        let outcome = try ConfigStore.initialize(paths: target, detected: DetectedEnvironment(), force: true)
        guard case .replaced(let backup) = outcome else { Issue.record("expected a replacement, got \(outcome)"); return }
        #expect(backup.lastPathComponent.hasPrefix("config.toml.bak-"))
        #expect(try String(contentsOf: backup, encoding: .utf8) == "# my hand-made settings\n")
        #expect(try String(contentsOf: target.configFile, encoding: .utf8) != "# my hand-made settings\n")
    }

    @Test func twoBackupsInTheSameSecondDoNotCollide() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        try "a".write(to: target.configFile, atomically: true, encoding: .utf8)
        let now = Date()
        let first = try ConfigStore.initialize(paths: target, detected: DetectedEnvironment(), force: true, now: now)
        let second = try ConfigStore.initialize(paths: target, detected: DetectedEnvironment(), force: true, now: now)
        guard case .replaced(let one) = first, case .replaced(let two) = second else { Issue.record("expected replacements"); return }
        #expect(one != two)
        #expect(try String(contentsOf: one, encoding: .utf8) == "a")
    }

    @Test func theGeneratedTemplateParsesCleanly() {
        let text = ConfigTemplate.render(DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude", "codex"]))
        let result = ConfigParser.parse(text)
        #expect(result.diagnostics == [])
        #expect(result.config.terminal == "ghostty")
        #expect(result.config.editor == "vscode")
        #expect(result.config.enabledAgents == ["claude", "codex"])
    }

    @Test func theTemplateWithNothingDetectedParsesToDefaults() {
        let result = ConfigParser.parse(ConfigTemplate.render(DetectedEnvironment()))
        #expect(result.diagnostics == [])
        #expect(result.config == .default)
    }
}

@Suite("Detector")
struct DetectorTests {
    private func facts() -> FakeSystemFacts {
        FakeSystemFacts(applications: [
            "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
            "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        ])
    }

    @Test func detectsInstalledAppsAndAgentCommands() async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "claude\ncodex\n")])
        let detected = await Detector(facts: facts(), runner: runner).detect()
        #expect(detected == DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude", "codex"]))
    }

    @Test func asksTheLoginShellInteractively() async {
        let runner = FakeProcessRunner()
        _ = await Detector(facts: facts(), runner: runner).commandsFound(["claude", "codex"])
        let call = runner.recorded.first
        #expect(call?.executable == "/bin/zsh")
        #expect(call?.arguments.first == "-lic")
        let script = try? #require(call?.arguments[1])
        #expect(script?.contains("command -v") == true)
        // The names are operands after the script ($0 first), never part of it.
        #expect(script?.contains("claude") == false)
        #expect(Array(call?.arguments.dropFirst(2) ?? []) == ["rh-detect", "claude", "codex"])
    }

    @Test func fishGetsTheNamesAsArgvWithoutAZeroSlot() async {
        let runner = FakeProcessRunner()
        let fish = FakeSystemFacts(loginShell: "/opt/homebrew/bin/fish")
        _ = await Detector(facts: fish, runner: runner).commandsFound(["claude"])
        let call = runner.recorded.first
        #expect(call?.executable == "/opt/homebrew/bin/fish")
        #expect(call?.arguments.dropFirst(2).map { $0 } == ["claude"])
        #expect(call?.arguments[1].contains("$argv") == true)
    }

    @Test func aFailingShellFindsNothing() async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 1)])
        let found = await Detector(facts: facts(), runner: runner).commandsFound(["claude"])
        #expect(found.isEmpty)
    }
}
