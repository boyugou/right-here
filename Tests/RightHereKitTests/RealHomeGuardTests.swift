import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

/// None of these touch the real home: the home that is "real" here is a temporary folder, and the environment is the one the test hands over.
@Suite("RealHomeGuard: a process a test started does not change the real home")
struct RealHomeGuardTests {
    private let underTest = ["RH_NO_UI": "1"]

    @Test func aTestWithoutATrialHomeIsRefusedForTheRealHome() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        #expect(throws: RealHomeGuard.Refusal()) { try RealHomeGuard.check(home: home, environment: underTest, realHome: home) }
        #expect(throws: RealHomeGuard.Refusal()) { try RealHomeGuard.checkSystemWide(environment: underTest) }
    }

    @Test func aTrialHomeAnotherHomeAndAPersonAtTheKeyboardAreNotRefused() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let trial = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: trial) }
        try RealHomeGuard.check(home: home, environment: underTest.merging(["RH_HOME": trial.path]) { $1 }, realHome: home)
        try RealHomeGuard.check(home: trial, environment: underTest, realHome: home)
        try RealHomeGuard.check(home: home, environment: [:], realHome: home)
        try RealHomeGuard.checkSystemWide(environment: underTest.merging(["RH_HOME": trial.path]) { $1 })
        try RealHomeGuard.checkSystemWide(environment: [:])
    }

    @Test func aFileUnderTheRealHomeIsNotWrittenByATestWithoutATrialHome() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let elsewhere = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: elsewhere) }
        let config = home.appendingPathComponent(".config/right-here/config.toml")
        #expect(throws: RealHomeGuard.Refusal()) { try RealHomeGuard.checkWriting(config, environment: underTest, realHome: home) }
        #expect(throws: RealHomeGuard.Refusal()) { try RealHomeGuard.checkWriting(home, environment: underTest, realHome: home) }
        // A link under the real home to a file elsewhere is that file; a link elsewhere to a file under the real home is a file of the home.
        let link = elsewhere.appendingPathComponent("link.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: config)
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: config, atomically: true, encoding: .utf8)
        #expect(throws: RealHomeGuard.Refusal()) { try RealHomeGuard.checkWriting(link, environment: underTest, realHome: home) }
        // Not the real home: a folder that only starts with the same letters, another folder, a trial home, a person at the keyboard.
        let sibling = URL(fileURLWithPath: home.path + "-other/.config/right-here/config.toml")
        try RealHomeGuard.checkWriting(sibling, environment: underTest, realHome: home)
        try RealHomeGuard.checkWriting(elsewhere.appendingPathComponent("config.toml"), environment: underTest, realHome: home)
        try RealHomeGuard.checkWriting(config, environment: underTest.merging(["RH_HOME": elsewhere.path]) { $1 }, realHome: home)
        try RealHomeGuard.checkWriting(config, environment: [:], realHome: home)
    }

    @Test func everyWayTheInstallerWritesIsRefusedAndLeavesNothing() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home, environment: underTest, realHome: home)
        #expect(throws: RealHomeGuard.Refusal()) { try installer.installRunnerScript(rhPath: "/opt/app/rh") }
        #expect(throws: RealHomeGuard.Refusal()) { try installer.installCLILink(rhPath: "/opt/app/rh") }
        #expect(throws: RealHomeGuard.Refusal()) { try installer.installServices([]) }
        #expect(throws: RealHomeGuard.Refusal()) { try installer.removeServices() }
        #expect(throws: RealHomeGuard.Refusal()) { try installer.removeRunnerScript() }
        #expect(throws: RealHomeGuard.Refusal()) { _ = try installer.removeCLILink() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.path).isEmpty, "nothing was made under the home")
    }

    @Test func theSameInstallerWritesWhenTheProcessIsNotATestOrHasATrialHome() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home, environment: [:], realHome: home)
        let rh = "/Applications/Right Here.app/Contents/Helpers/rh"
        try installer.installRunnerScript(rhPath: rh)
        try installer.installCLILink(rhPath: rh)
        #expect(installer.installedRunnerTarget() == rh)
        #expect(try installer.removeCLILink() == .removed(destination: rh))
        try installer.removeRunnerScript()
        #expect(installer.installedRunnerTarget() == nil)
    }

    @Test func aLinkThatIsNotRightHeresIsLeftAloneAndSaidSo() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home, environment: [:], realHome: home)
        try FileManager.default.createDirectory(at: installer.locations.localBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: installer.cliLink.path, withDestinationPath: "/usr/local/bin/rh")
        #expect(try installer.removeCLILink() == .foreign(destination: "/usr/local/bin/rh"))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path)) == "/usr/local/bin/rh", "the link is still there")
        let none = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: none) }
        #expect(try Installer(home: none, environment: [:], realHome: none).removeCLILink() == .absent)
    }

    @Test func theRegistrationOfTheFinderExtensionIsRefusedBeforePluginkitIsAsked() async {
        let runner = FakeProcessRunner()
        let manager = FinderExtensionManager(runner: runner, environment: underTest)
        await #expect(throws: RealHomeGuard.Refusal()) { try await manager.register(appexPath: "/x/FinderExtension.appex") }
        await #expect(throws: RealHomeGuard.Refusal()) { try await manager.unregister(appexPath: "/x/FinderExtension.appex") }
        await #expect(throws: RealHomeGuard.Refusal()) { try await manager.disable() }
        #expect(runner.recorded.isEmpty, "pluginkit was started: \(runner.recorded)")
        _ = await manager.status()
        #expect(runner.recorded.count == 1, "looking at the registration changes nothing and is allowed")
    }
}
