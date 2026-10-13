import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("ConfigStore: overlay")
struct ConfigOverlayStoreTests {
    private func paths(in directory: URL) -> RHPaths {
        RHPaths(environment: ["RH_CONFIG_DIR": directory.path], home: directory)
    }

    @Test func theOverlayIsReadWithTheConfig() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        try "[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\n".write(to: directory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try "[general]\nterminal = \"terminal\"\n".write(to: directory.appendingPathComponent("config.local.toml"), atomically: true, encoding: .utf8)
        let loaded = ConfigStore.load(paths: paths(in: directory))
        #expect(loaded.fileExists && loaded.localFileExists)
        #expect(loaded.config.terminal == "terminal")
        #expect(loaded.config.editor == "vscode")
    }

    @Test func anOverlayAloneIsEnough() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        try "[general]\nterminal = \"terminal\"\n".write(to: directory.appendingPathComponent("config.local.toml"), atomically: true, encoding: .utf8)
        let loaded = ConfigStore.load(paths: paths(in: directory))
        #expect(!loaded.fileExists)
        #expect(loaded.localFileExists)
        #expect(loaded.config.terminal == "terminal")
    }

    @Test func noOverlayMeansTheFileAsItWas() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = ConfigStore.load(paths: paths(in: directory))
        #expect(!loaded.localFileExists)
        #expect(loaded.localFile.lastPathComponent == "config.local.toml")
    }

    @Test func theOverlayNameFollowsTheConfigFileName() {
        let custom = RHPaths(environment: ["RH_CONFIG": "/tmp/rh-x/custom.toml"], home: URL(fileURLWithPath: "/Users/tester"))
        #expect(custom.localConfigFile.path == "/tmp/rh-x/custom.local.toml")
        let usual = RHPaths(environment: [:], home: URL(fileURLWithPath: "/Users/tester"))
        #expect(usual.localConfigFile.path == "/Users/tester/.config/right-here/config.local.toml")
        #expect(usual.syncStateFile.path == "/Users/tester/.config/right-here/sync.toml")
    }

    @Test func anOversizedOverlayIsRefusedAndNamed() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        try "[general]\nterminal = \"terminal\"\n".write(to: directory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try ("# " + String(repeating: "x", count: ConfigParser.maxBytes + 10) + "\n").write(to: directory.appendingPathComponent("config.local.toml"), atomically: true, encoding: .utf8)
        let loaded = ConfigStore.load(paths: paths(in: directory))
        #expect(loaded.result.diagnostics.contains { $0.file == "config.local.toml" && $0.message.contains("a few kilobytes") })
        #expect(loaded.config.terminal == "terminal")
    }

    @Test func aDiagnosticFromTheOverlaySaysSo() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        try "[general\n".write(to: directory.appendingPathComponent("config.local.toml"), atomically: true, encoding: .utf8)
        let loaded = ConfigStore.load(paths: paths(in: directory))
        let first = try #require(loaded.result.diagnostics.first)
        #expect(first.summary(file: loaded.file).hasPrefix("error: config.local.toml:1"))
    }

    @Test func theStampChangesWhenOnlyTheOverlayChanges() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let paths = paths(in: directory)
        try "# base\n".write(to: paths.configFile, atomically: true, encoding: .utf8)
        let before = ConfigStore.stamp(paths: paths)
        try "[general]\nterminal = \"terminal\"\n".write(to: paths.localConfigFile, atomically: true, encoding: .utf8)
        let created = ConfigStore.stamp(paths: paths)
        #expect(created != before)
        // A copy that keeps an old date (`cp -p`, a sync tool) is older than the config and still a change.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: paths.localConfigFile.path)
        let older = ConfigStore.stamp(paths: paths)
        #expect(older != created)
        #expect(older != before)
        try FileManager.default.removeItem(at: paths.localConfigFile)
        #expect(ConfigStore.stamp(paths: paths) == before)
    }

    @Test func theDoctorMentionsTheOverlay() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let paths = paths(in: directory)
        try "[general]\nterminal = \"terminal\"\n".write(to: paths.configFile, atomically: true, encoding: .utf8)
        let without = Doctor(paths: paths, loaded: ConfigStore.load(paths: paths), runner: FakeProcessRunner(), rhPath: nil).configCheck()
        #expect(without.status == .ok)
        #expect(without.notes.isEmpty)
        try "[general]\neditor = \"vscode\"\n".write(to: paths.localConfigFile, atomically: true, encoding: .utf8)
        let with = Doctor(paths: paths, loaded: ConfigStore.load(paths: paths), runner: FakeProcessRunner(), rhPath: nil).configCheck()
        #expect(with.status == .ok)
        #expect(with.notes.count == 1)
        #expect(with.notes.first?.english().contains("per-machine overlay") == true)
        #expect(with.notes.first?.english().contains("config.local.toml") == true)
    }
}
