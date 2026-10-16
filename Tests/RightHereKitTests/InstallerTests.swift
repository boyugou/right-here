import Foundation
import Synchronization
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

    @Test("the runner target survives quoting round trips", arguments: ["/usr/local/bin/rh", "/Users/me/My Tools/rh", "/Users/o'brien/bin/rh", "/a \"$@\"/rh", "/line\nbreak/rh"])
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

    /// Runs the installed runner script, with a fake `rh` that records that it was called.
    private func runRunner(_ arguments: [String]) throws -> (status: Int32, called: Bool, standardError: String) {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let marker = home.appendingPathComponent("called")
        let fake = home.appendingPathComponent("fake rh")
        try "#!/bin/sh\ntouch '\(marker.path)'\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let installer = Installer(home: home)
        try installer.installRunnerScript(rhPath: fake.path)
        let process = Process()
        process.executableURL = installer.runnerScript
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, FileManager.default.fileExists(atPath: marker.path), text)
    }

    @Test("the runner passes on only run and probe", arguments: ["run", "probe"])
    func runnerAllowsRunAndProbe(subcommand: String) throws {
        let result = try runRunner([subcommand, "x"])
        #expect(result.status == 0)
        #expect(result.called)
    }

    @Test("the runner refuses everything else, so a compromised extension cannot reconfigure the machine",
          arguments: ["setup", "install", "uninstall", "init", "config", "mcp", "doctor", "--version", "-h", ""])
    func runnerRefusesOtherSubcommands(subcommand: String) throws {
        let result = try runRunner(subcommand.isEmpty ? [] : [subcommand, "--force"])
        #expect(result.status == 64)
        #expect(!result.called, "the runner started rh for \(subcommand.debugDescription)")
        #expect(result.standardError.contains("refusing"))
    }

    @Test func theRunnerScriptIsCurrentOnlyWhenItIsExactlyWhatWouldBeWritten() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        #expect(!installer.runnerScriptIsCurrent(rhPath: "/opt/rh/bin/rh"))
        try installer.installRunnerScript(rhPath: "/opt/rh/bin/rh")
        #expect(installer.runnerScriptIsCurrent(rhPath: "/opt/rh/bin/rh"))
        #expect(!installer.runnerScriptIsCurrent(rhPath: "/other/rh"))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: installer.runnerScript.path)
        #expect(!installer.runnerScriptIsCurrent(rhPath: "/opt/rh/bin/rh"), "a script that cannot be run is not current")
        try installer.installRunnerScript(rhPath: "/opt/rh/bin/rh")
        try (Installer.runnerScriptText(rhPath: "/opt/rh/bin/rh") + "# edited\n").write(to: installer.runnerScript, atomically: true, encoding: .utf8)
        #expect(!installer.runnerScriptIsCurrent(rhPath: "/opt/rh/bin/rh"))
    }

    private func spec(_ title: String, command: String = "rh run x") -> ServiceSpec {
        ServiceSpec(title: title, actionID: "open.terminal", input: .folders, command: command)
    }

    @Test func theServicesAreCurrentOnlyWhenEveryBundleAndBothOfItsFilesAreWhatWouldBeWritten() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let specs = [spec("Open in Ghostty"), spec("Codex Here")]
        #expect(!installer.servicesAreCurrent(specs))
        try installer.installServices(specs)
        #expect(installer.servicesAreCurrent(specs))
        #expect(installer.servicesAreCurrent(specs + [spec("Open in Ghostty")]), "two actions with one title are one Service")
        #expect(!installer.servicesAreCurrent([spec("Open in Ghostty")]), "a Service the config no longer asks for is stale")
        #expect(!installer.servicesAreCurrent(specs + [spec("New Markdown")]), "a Service the config asks for and is missing")
        #expect(!installer.servicesAreCurrent([spec("Open in Ghostty", command: "rh run y"), spec("Codex Here")]), "a command that points elsewhere")
        let document = installer.locations.services.appendingPathComponent("Right Here - Codex Here.workflow/Contents/document.wflow")
        try Data("edited".utf8).write(to: document)
        #expect(!installer.servicesAreCurrent(specs), "a changed file is not current")
    }

    /// One test and not a parameterized one: `script/mutation_check.py` reads a failed test by its name.
    @Test func theRunnerRefusesSetupAndTheOtherCommandsThatChangeTheMachine() throws {
        for subcommand in ["setup", "install", "uninstall", "init"] {
            let result = try runRunner([subcommand, "--force"])
            #expect(result.status == 64, "\(subcommand): status \(result.status)")
            #expect(!result.called, "the runner started rh for \(subcommand)")
        }
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

    @Test("an app run from App Translocation is recognized", arguments: [
        ("/private/var/folders/ab/cd/T/AppTranslocation/6F1B/d/Right Here.app/Contents/Helpers/rh", true),
        ("/Applications/Right Here.app/Contents/Helpers/rh", false),
        ("/Users/tester/Applications/Right Here.app/Contents/Helpers/rh", false)
    ])
    func translocation(path: String, translocated: Bool) {
        #expect(InstallError.isTranslocated(path) == translocated)
    }

    @Test func aHomebrewInstallKeepsThePrefixPathInsteadOfTheVersionedCellarPath() throws {
        let prefix = try makeTemporaryDirectory().appendingPathComponent("opt/homebrew")
        defer { try? FileManager.default.removeItem(at: prefix.deletingLastPathComponent().deletingLastPathComponent()) }
        let cellar = prefix.appendingPathComponent("Cellar/rh/0.1.0/bin")
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try "binary".write(to: cellar.appendingPathComponent("rh"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: prefix.appendingPathComponent("bin/rh").path, withDestinationPath: "../Cellar/rh/0.1.0/bin/rh")
        let resolved = cellar.appendingPathComponent("rh").resolvingSymlinksInPath().path
        let stable = Installer.stablePath(forResolved: resolved)
        #expect(stable.hasSuffix("/opt/homebrew/bin/rh"))
        #expect(URL(fileURLWithPath: stable).resolvingSymlinksInPath().path == resolved)
    }

    @Test func aCellarPathWithoutAMatchingPrefixLinkIsKept() {
        #expect(Installer.stablePath(forResolved: "/nowhere/Cellar/rh/0.1.0/bin/rh") == "/nowhere/Cellar/rh/0.1.0/bin/rh")
        #expect(Installer.stablePath(forResolved: "/Applications/Right Here.app/Contents/Helpers/rh") == "/Applications/Right Here.app/Contents/Helpers/rh")
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

    @Test func aPathMacOSWouldNotShowOffersTheFilesAndFoldersPage() {
        let content = FailureAlert.content(for: PlanError.unreadable("/Users/me/Documents/project"), action: "open.terminal")
        #expect(content.message.contains("/Users/me/Documents/project"))
        #expect(content.settingsURL == FailureAlert.filesAndFoldersSettingsURL)
        #expect(content.settingsURL?.absoluteString.hasSuffix("Privacy_FilesAndFolders") == true)
    }

    @Test("an alert is shown only for a real run that asked for one, and never when UI is switched off", arguments: [
        (true, false, [String: String](), true),
        (false, false, [:], false),
        (true, true, [:], false),
        (true, false, ["RH_NO_UI": "1"], false),
        (true, true, ["RH_NO_UI": "1"], false)
    ])
    func whenAnAlertMayAppear(requested: Bool, dryRun: Bool, environment: [String: String], expected: Bool) {
        #expect(FailureAlert.shouldShow(requested: requested, dryRun: dryRun, environment: environment) == expected)
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

    @Test func twoActionsWithOneTitleInstallOneService() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let same = [specs[0], ServiceSpec(title: "Open in Ghostty", actionID: "open.terminal@ghostty", command: "echo three"), specs[1]]
        let written = try installer.installServices(same)
        #expect(written.map(\.lastPathComponent) == ["Right Here - Open in Ghostty.workflow", "Right Here - Claude Code Here.workflow"])
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


@Suite("FinderExtensionManager: a registration has to stay")
struct ExtensionRegistrationTests {
    private let appex = "/Users/me/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex"
    private var listed: String { "+    \(AppIdentity.extensionBundleID)(0.1.0)\tAAAA-BBBB\t2026-10-12 16:24:09 +0000\t\(appex)\n" }

    @Test func aRegistrationThatStaysIsNotRepeated() async throws {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0), ProcessResult(status: 0), ProcessResult(status: 0, standardOutput: listed)])
        let again = try await FinderExtensionManager(runner: runner).registerAndConfirm(appexPath: appex, settle: .zero)
        #expect(!again)
        #expect(runner.recorded.map { $0.arguments.first } == ["-a", "-e", "-m"], "register, enable, then one look")
    }

    @Test func aRegistrationThatVanishedIsMadeOnceMore() async throws {
        let runner = FakeProcessRunner(results: [
            ProcessResult(status: 0), ProcessResult(status: 0),          // register, enable
            ProcessResult(status: 0, standardOutput: ""),                // pluginkit no longer knows the extension
            ProcessResult(status: 0), ProcessResult(status: 0)           // register, enable again
        ])
        let again = try await FinderExtensionManager(runner: runner).registerAndConfirm(appexPath: appex, settle: .zero)
        #expect(again)
        #expect(runner.recorded.map { $0.arguments.first } == ["-a", "-e", "-m", "-a", "-e"])
        #expect(runner.recorded.last?.arguments == ["-e", "use", "-i", AppIdentity.extensionBundleID])
    }

    @Test func anExtensionThatIsRegisteredButSwitchedOffIsEnabledAgainToo() async throws {
        let off = "-    \(AppIdentity.extensionBundleID)(0.1.0)\tAAAA\t2026-10-12 16:24:09 +0000\t\(appex)\n"
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0), ProcessResult(status: 0), ProcessResult(status: 0, standardOutput: off), ProcessResult(status: 0), ProcessResult(status: 0)])
        #expect(try await FinderExtensionManager(runner: runner).registerAndConfirm(appexPath: appex, settle: .zero))
    }
}


@Suite("Installer.unquote")
struct UnquoteTests {
    @Test("unquote undoes ShellQuoting.quote, even where a quote is followed by a combining mark", arguments: [
        "/Users/me/plain", "/Users/me/it's here", "/Users/me/a'b'c", "/Users/me/q'\u{301}x", "/Users/me/q'\u{FE0F}x", "/Users/me/q'\u{20E3}x",
        "/Users/me/''", "/Users/me/'", "/Users/me/日本語 'x'", "/a'\u{200D}'\u{301}b"
    ])
    func roundTrip(path: String) {
        #expect(Installer.unquote(ShellQuoting.quote(path)) == path, "\(path.debugDescription) came back as \(Installer.unquote(ShellQuoting.quote(path)).debugDescription)")
    }

    @Test func aWordThatIsNotQuotedIsLeftAlone() {
        #expect(Installer.unquote("/bin/rh") == "/bin/rh")
        #expect(Installer.unquote("'") == "'")
        #expect(Installer.unquote("") == "")
    }

    @Test func theRunnerScriptTargetSurvivesAHostilePath() throws {
        let path = "/Users/me/Apps/it's\u{301} here/Right Here.app/Contents/Helpers/rh"
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        try installer.installRunnerScript(rhPath: path)
        #expect(installer.installedRunnerTarget() == path)
    }
}

@Suite("Installer: a failure halfway keeps what was installed")
struct InstallerAtomicityTests {
    private struct Boom: Error {}

    @Test func aFailureWhileWritingAServiceLeavesTheOnesThatWereThere() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let before = [ServiceSpec(title: "Open in Ghostty", actionID: "open.terminal", command: "echo one")]
        try installer.installServices(before)
        let installed = installer.installedServices().map(\.lastPathComponent)
        #expect(installed.count == 1)

        let after = [ServiceSpec(title: "Claude Code Here", actionID: "agent.claude", command: "echo two"),
                     ServiceSpec(title: "Codex Here", actionID: "agent.codex", command: "echo three")]
        var written = 0
        #expect(throws: Boom.self) {
            try installer.installServices(after) { spec, bundle in
                written += 1
                if written == 2 { throw Boom() }
                try Installer.writeWorkflow(spec, to: bundle)
            }
        }
        #expect(installer.installedServices().map(\.lastPathComponent) == installed)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installer.locations.services.path).filter { $0.hasPrefix(".rh-staging") }
        #expect(leftovers.isEmpty)
    }

    private func sevenSpecs() -> [ServiceSpec] {
        ["Open in Ghostty", "Open in Visual Studio Code", "Claude Code Here", "Codex Here", "New Markdown Document", "Copy Absolute Path", "Copy Path From Git Root"]
            .enumerated().map { ServiceSpec(title: $1, actionID: "open.terminal", input: .folders, command: "echo \($0)") }
    }

    @Test func twoInstallsAtOnceBothSucceedAndLeaveEveryQuickAction() throws {
        // The setup window and `rh setup` in a terminal at the same moment: one removed the bundles the other was about to remove or move, and
        // one of them failed ("couldn't be removed", "couldn't be moved") in 19 of 20 rounds, and could leave some Quick Actions missing.
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let wanted = sevenSpecs()
        let problems = Mutex<[String]>([])
        for round in 0..<20 {
            DispatchQueue.concurrentPerform(iterations: 2) { _ in
                do { _ = try installer.installServices(wanted) } catch { problems.withLock { $0.append("round \(round): an install failed: \(error.localizedDescription)") } }
            }
            if !installer.servicesAreCurrent(wanted) {
                problems.withLock { $0.append("round \(round): after both ended, \(installer.installedServices().count) of \(wanted.count) Quick Actions are there") }
            }
        }
        #expect(problems.withLock { $0 }.isEmpty, "\(problems.withLock { $0 }.count) of 20 rounds went wrong; the first: \(problems.withLock { $0 }.first ?? "")")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installer.locations.services.path).filter { $0.hasPrefix(".rh-staging") }
        #expect(leftovers.isEmpty, "\(leftovers)")
    }

    @Test func aQuickActionIsNeverMissingWhileItIsReplacedByAnInstall() throws {
        // Removing every bundle and then moving the new ones in left a moment in which Finder had no Quick Actions at all (and a kill in
        // that moment left none). Each bundle takes the place of the one of its name in one step.
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let wanted = sevenSpecs()
        try installer.installServices(wanted)
        let names = Set(installer.installedServices().map(\.lastPathComponent))
        let installing = Mutex(true)
        let missing = Mutex<[String]>([])
        let reader = Thread {
            while installing.withLock({ $0 }) {
                let present = Set(installer.installedServices().map(\.lastPathComponent))
                if present != names { missing.withLock { $0.append("\(names.subtracting(present))") } }
            }
        }
        reader.start()
        for _ in 0..<60 { try installer.installServices(wanted) }
        installing.withLock { $0 = false }
        #expect(missing.withLock { $0 }.isEmpty, "the Quick Actions were not all there \(missing.withLock { $0 }.count) times; the first: \(missing.withLock { $0 }.first ?? "")")
    }

    @Test func aServiceTheConfigNoLongerAsksForGoesAfterTheNewOnesAreIn() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let wanted = sevenSpecs()
        try installer.installServices(wanted)
        try installer.installServices(Array(wanted.prefix(2)))
        #expect(installer.installedServices().count == 2)
        // One that is gone already, which another install removed, is as good as one that was removed.
        try installer.removeServices()
        try installer.removeServices()
        #expect(installer.installedServices().isEmpty)
    }

    @Test func replacingTheCommandLinkNeverLeavesItMissingOrADuplicate() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        try installer.installCLILink(rhPath: "/opt/old/rh")
        try installer.installCLILink(rhPath: "/opt/new/rh")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path) == "/opt/new/rh")
        let names = try FileManager.default.contentsOfDirectory(atPath: installer.cliLink.deletingLastPathComponent().path)
        #expect(names == ["rh"], "\(names)")
    }
}

