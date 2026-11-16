import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("The setup window reads and recovers both config files")
struct SetupConfigRecoveryTests {
    private func paths(_ home: URL) -> RHPaths {
        RHPaths(environment: ["RH_CONFIG": home.appendingPathComponent("preferences/custom settings.toml").path], home: home)
    }

    private func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    @Test func aProblemInACustomNamedOverlayOpensThatFileAndAnExplicitChoiceWins() async throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = paths(home)
        try write("[general]\nterminal = \"terminal\"\n", to: paths.configFile)
        try write("[general]\nterminal = \"does-not-exist\"\n", to: paths.localConfigFile)
        let runner = FakeProcessRunner()
        let actions = SetupActions(facts: FakeSystemFacts(homeDirectory: home), paths: paths, runner: runner, helperPath: "/opt/rh", trialHome: home)
        #expect(await actions.configRecoveryTarget() == .local)
        #expect(await actions.openConfig() == nil)
        #expect(runner.recorded.last?.arguments == ["-t", paths.localConfigFile.path])
        #expect(await actions.openConfig(target: .shared) == nil)
        #expect(runner.recorded.last?.arguments == ["-t", paths.configFile.path])
    }

    @Test func anExplicitMissingFileNeverFallsBackOrGetsCreated() async throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = paths(home)
        try write("[general]\n", to: paths.configFile)
        let runner = FakeProcessRunner()
        let actions = SetupActions(facts: FakeSystemFacts(homeDirectory: home), paths: paths, runner: runner, helperPath: "/opt/rh", trialHome: home)
        #expect(await actions.openConfig(target: .local) == .explained([.refusalPathNotFound(paths.localConfigFile.path)]))
        #expect(runner.recorded.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: paths.localConfigFile.path))
    }

    @Test func errorsLeadWarningsAndAnOverlayDanglingLinkLeadsTheSharedFile() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = paths(home)
        try write("[general]\nunknown_key = true\n", to: paths.configFile)
        try write("[general]\nterminal = 3\n", to: paths.localConfigFile)
        #expect(ConfigStore.load(paths: paths).recoveryTarget == .local)
        try FileManager.default.removeItem(at: paths.localConfigFile)
        try FileManager.default.createSymbolicLink(at: paths.localConfigFile, withDestinationURL: home.appendingPathComponent("not-cloned/settings.toml"))
        #expect(ConfigStore.load(paths: paths).recoveryTarget == .local)
    }

    @Test func sourcesNoticeCommentEditsEvenWithTheSameFileDate() async throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = paths(home)
        let text = "[general]\nterminal = \"terminal\"\n"
        try write(text, to: paths.configFile)
        let date = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: paths.configFile.path)
        let loader = SetupLoader(facts: FakeSystemFacts(homeDirectory: home), paths: paths, runner: FakeProcessRunner(), helperPath: "/opt/rh")
        let before = await loader.configState()
        try write(text + "# changed outside\n", to: paths.configFile)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: paths.configFile.path)
        let comment = await loader.configState()
        #expect(comment != before && !comment.changesSettings(from: before))
        try write("[general]\nterminal = \"ghostty\"\n", to: paths.configFile)
        let changed = await loader.configState()
        #expect(changed.changesSettings(from: comment))
    }

    @Test func aRepointedDanglingLinkIsANewStateWithoutStartingProcesses() async throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = paths(home)
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: paths.configFile.path, withDestinationPath: "first.toml")
        let runner = FakeProcessRunner()
        let loader = SetupLoader(facts: FakeSystemFacts(homeDirectory: home), paths: paths, runner: runner, helperPath: "/opt/rh")
        let before = await loader.configState()
        try FileManager.default.removeItem(at: paths.configFile)
        try FileManager.default.createSymbolicLink(atPath: paths.configFile.path, withDestinationPath: "second.toml")
        let after = await loader.configState()
        #expect(before != after && after.changesSettings(from: before))
        #expect(runner.recorded.isEmpty)
    }
}
