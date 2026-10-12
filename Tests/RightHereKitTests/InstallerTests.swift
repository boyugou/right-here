import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("Installer")
struct InstallerTests {
    @Test func runnerScriptHandsOverToRhRunWithTheAbsolutePath() {
        let text = Installer.runnerScriptText(rhPath: "/Applications/Right Here.app/Contents/Helpers/rh")
        #expect(text.hasPrefix("#!/bin/zsh -f\n"))
        #expect(text.contains("exec '/Applications/Right Here.app/Contents/Helpers/rh' \"$@\""))
    }

    @Test func installsTheRunnerScriptExecutableUnderTheExtensionsFolder() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let script = try installer.installRunnerScript(rhPath: "/opt/homebrew/bin/rh")
        #expect(script.path == home.path + "/Library/Application Scripts/com.boyugou.righthere.FinderExtension/rh-run")
        let attributes = try FileManager.default.attributesOfItem(atPath: script.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o755)
        #expect(installer.installedRunnerTarget() == "/opt/homebrew/bin/rh")
    }

    @Test("the runner target survives quoting round trips", arguments: ["/usr/local/bin/rh", "/Users/me/My Tools/rh", "/Users/o'brien/bin/rh"])
    func targetRoundTrip(path: String) throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        try installer.installRunnerScript(rhPath: path)
        #expect(installer.installedRunnerTarget() == path)
    }

    @Test func theRunnerScriptReallyRunsRhWithItsArguments() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let fake = home.appendingPathComponent("fake rh")
        try "#!/bin/sh\nprintf '%s|' \"$@\"\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let installer = Installer(home: home)
        try installer.installRunnerScript(rhPath: fake.path)
        let output = try Shell.run(installer.runnerScript.path, args: ["run", "--alert", "copy-path.absolute", "--origin", "items", "--", "/tmp/a b"])
        #expect(output == "run|--alert|copy-path.absolute|--origin|items|--|/tmp/a b|")
    }

    @Test func cliLinkIsReplacedWhenItAlreadyExists() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        try installer.installCLILink(rhPath: "/old/rh")
        try installer.installCLILink(rhPath: "/new/rh")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path) == "/new/rh")
    }

    @Test func aRealFileInThePlaceOfTheLinkIsLeftAlone() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        try FileManager.default.createDirectory(at: installer.locations.localBin, withIntermediateDirectories: true)
        try "#!/bin/sh\necho mine\n".write(to: installer.cliLink, atomically: true, encoding: .utf8)
        #expect(throws: InstallError.notALink(path: installer.cliLink.path)) { try installer.installCLILink(rhPath: "/new/rh") }
        #expect(try String(contentsOf: installer.cliLink, encoding: .utf8) == "#!/bin/sh\necho mine\n")
    }

    @Test func aDanglingLinkIsReplaced() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        try FileManager.default.createDirectory(at: installer.locations.localBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: installer.cliLink.path, withDestinationPath: "/gone/rh")
        try installer.installCLILink(rhPath: "/new/rh")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path) == "/new/rh")
    }

    @Test func removeRunnerScriptIsIdempotent() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        try installer.removeRunnerScript()
        try installer.installRunnerScript(rhPath: "/x/rh")
        try installer.removeRunnerScript()
        #expect(installer.installedRunnerTarget() == nil)
    }
}

@Suite("FinderExtensionManager")
struct FinderExtensionManagerTests {
    private let id = AppIdentity.extensionBundleID

    @Test func parsesAnEnabledExtension() {
        let output = "+    \(id)(1.0)\tA0C41BB7-BA7C-47C1-9D27-287469429570\t2026-10-11 23:29:41 +0000\t/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex\n (1 plug-in)\n"
        let status = FinderExtensionManager.parse(output)
        #expect(status.state == .enabled)
        #expect(status.paths == ["/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex"])
    }

    @Test func parsesADisabledExtension() {
        let output = "-    \(id)(1.0)\tUUID\t2026-10-11 23:29:41 +0000\t/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex\n"
        #expect(FinderExtensionManager.parse(output).state == .disabled)
    }

    @Test func noOutputMeansNotRegistered() {
        let status = FinderExtensionManager.parse("")
        #expect(status.state == .notRegistered)
        #expect(status.paths.isEmpty)
    }

    @Test func severalCopiesAreAllReported() {
        let output = """
        +    \(id)(1.0)\tU1\t2026-10-11 23:29:41 +0000\t/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex
             \(id)(1.0)\tU2\t2026-10-11 23:20:00 +0000\t/Users/x/DerivedData/Build/Right Here.app/Contents/PlugIns/FinderExtension.appex
        """
        let status = FinderExtensionManager.parse(output)
        #expect(status.state == .enabled)
        #expect(status.paths.count == 2)
    }

    @Test func otherExtensionsAreIgnored() {
        let output = "+    com.bandisoft.mac.bandizip.findersyncextension(7.22)\tU\t2026-10-11\t/Applications/Bandizip.app/Contents/PlugIns/B.appex\n"
        #expect(FinderExtensionManager.parse(output).state == .notRegistered)
    }

    @Test func registerAddsThenEnables() async throws {
        let runner = FakeProcessRunner()
        try await FinderExtensionManager(runner: runner).register(appexPath: "/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex")
        #expect(runner.recorded.map(\.arguments) == [
            ["-a", "/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex"],
            ["-e", "use", "-i", id]
        ])
    }

    @Test func aFailingPluginkitIsReported() async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 1, standardError: "no such plug-in")])
        await #expect(throws: ExecutionError.self) { try await FinderExtensionManager(runner: runner).disable() }
    }
}

@Suite("FailureAlert")
struct FailureAlertTests {
    @Test func aDeniedAutomationOffersTheSettingsPage() {
        let content = FailureAlert.content(for: ExecutionError.automationDenied(application: "Ghostty"), action: "agent.claude")
        #expect(content.message.contains("Ghostty"))
        #expect(content.settingsURL == FailureAlert.automationSettingsURL)
    }

    @Test func otherFailuresNameTheAction() {
        let content = FailureAlert.content(for: PlanError.appNotInstalled("Zed"), action: "open.app.zed")
        #expect(content.message.contains("Zed is not installed."))
        #expect(content.message.contains("open.app.zed"))
        #expect(content.settingsURL == nil)
    }
}

@Suite("Installer services")
struct InstallerServicesTests {
    private let specs = [
        ServiceSpec(title: "Open in Ghostty", actionID: "open.terminal", command: "echo one"),
        ServiceSpec(title: "Claude Code Here", actionID: "agent.claude", command: "echo two")
    ]

    @Test func writesLoadableWorkflowBundles() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let written = try installer.installServices(specs)
        #expect(written.map(\.lastPathComponent) == ["Right Here - Open in Ghostty.workflow", "Right Here - Claude Code Here.workflow"])
        for bundle in written {
            for file in ["Info.plist", "document.wflow"] {
                let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/\(file)"))
                #expect((try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]) != nil)
            }
        }
    }

    @Test func reinstallingReplacesWhatWasThereAndLeavesOtherServicesAlone() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let foreign = installer.locations.services.appendingPathComponent("Claude - ask.workflow")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)

        try installer.installServices(specs)
        try installer.installServices([specs[0]])
        #expect(installer.installedServices().map(\.lastPathComponent) == ["Right Here - Open in Ghostty.workflow"])
        #expect(FileManager.default.fileExists(atPath: foreign.path))

        try installer.removeServices()
        #expect(installer.installedServices().isEmpty)
        #expect(FileManager.default.fileExists(atPath: foreign.path))
    }
}
