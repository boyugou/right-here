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

    @Test func initializeWritesOnceAndDoesNotOverwrite() throws {
        let directory = try makeTemporaryDirectory().appendingPathComponent("nested")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let target = paths(in: directory)
        #expect(try ConfigStore.initialize(paths: target, detected: DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude"])))
        let first = try String(contentsOf: target.configFile, encoding: .utf8)
        #expect(!(try ConfigStore.initialize(paths: target, detected: DetectedEnvironment())))
        #expect(try String(contentsOf: target.configFile, encoding: .utf8) == first)
        #expect(try ConfigStore.initialize(paths: target, detected: DetectedEnvironment(), force: true))
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
        let runner = FakeRunner(results: [ProcessResult(status: 0, standardOutput: "claude\ncodex\n")])
        let detected = await Detector(facts: facts(), runner: runner).detect()
        #expect(detected == DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude", "codex"]))
    }

    @Test func asksTheLoginShellInteractively() async {
        let runner = FakeRunner()
        _ = await Detector(facts: facts(), runner: runner).commandsFound(["claude", "codex"])
        let call = runner.recorded.first
        #expect(call?.executable == "/bin/zsh")
        #expect(call?.arguments.first == "-lic")
        #expect(call?.arguments.last?.contains("command -v") == true)
    }

    @Test func aFailingShellFindsNothing() async {
        let runner = FakeRunner(results: [ProcessResult(status: 1)])
        let found = await Detector(facts: facts(), runner: runner).commandsFound(["claude"])
        #expect(found.isEmpty)
    }
}
