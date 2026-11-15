import Foundation
import Synchronization
import Testing
import RightHereCore
import RightHereKit
@testable import AppModel

/// Answers the questions the window asks of the Mac as a scripted Mac would: pluginkit says whether the Finder extension is switched on, the login shell finds no agent
/// command, everything else succeeds with nothing to say. It notes what it was asked.
private final class ScriptedMac: ProcessRunner, Sendable {
    private struct State {
        var calls: [ProcessStep] = []
        var extensionOn = false
    }

    private let state = Mutex(State())
    static let appex = "/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex"

    var calls: [ProcessStep] { state.withLock { $0.calls } }
    var pluginkitLooks: Int { calls.filter { $0.executable == "/usr/bin/pluginkit" && $0.arguments.first == "-m" }.count }
    func switchExtensionOn() { switchExtension(on: true) }
    func switchExtension(on: Bool) { state.withLock { $0.extensionOn = on } }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        let on = state.withLock { state -> Bool in
            state.calls.append(step)
            return state.extensionOn
        }
        if step.executable == "/usr/bin/pluginkit", step.arguments.first == "-m", on {
            return ProcessResult(status: 0, standardOutput: "+    \(AppIdentity.extensionBundleID)(0.3.0)\tAAAA\t2026-10-16 07:33:49 +0000\t\(Self.appex)\n")
        }
        return ProcessResult(status: 0)
    }
}

private final class Switch: Sendable {
    private let state: Mutex<Bool>
    init(_ on: Bool) { state = Mutex(on) }
    var isOn: Bool { state.withLock { $0 } }
    func set(_ on: Bool) { state.withLock { $0 = on } }
}

/// A Mac of made-up facts with a temporary home, and a window model over it. Nothing outside the home is touched, no process is started.
@MainActor
private struct Mac {
    let home: URL
    let paths: RHPaths
    let runner = ScriptedMac()
    let model: SetupModel
    private let visible: Switch

    static let inTheApplicationsFolder = "/Applications/Right Here.app/Contents/Helpers/rh"

    init(helper: String = Mac.inTheApplicationsFolder, visible: Bool = true, pollInterval: Duration = .milliseconds(10), idleInterval: Duration = .milliseconds(10),
         activationQuietPeriod: Duration = .zero) throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
        let facts = FakeSystemFacts(homeDirectory: home, directories: [home.path], applications: [
            "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
            "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        ])
        let flag = Switch(visible)
        self.visible = flag
        model = SetupModel(
            loader: SetupLoader(facts: facts, paths: paths, runner: runner, helperPath: helper, localizer: .english),
            actions: SetupActions(facts: facts, paths: paths, runner: runner, helperPath: helper, app: nil, trialHome: home),
            facts: facts, helper: helper, pollInterval: pollInterval, idleInterval: idleInterval,
            activationQuietPeriod: activationQuietPeriod, windowIsVisible: { flag.isOn })
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }
    func showWindow(_ shown: Bool) { visible.set(shown) }
    var configExists: Bool { FileManager.default.fileExists(atPath: paths.configFile.path) }

    func writeConfig(_ text: String = "[general]\n") throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try text.write(to: paths.configFile, atomically: true, encoding: .utf8)
    }

    /// Waits, a few milliseconds at a time, for `condition`; a test of a poll cannot know to the millisecond when it has looked.
    func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

@Suite("The setup window's model: the first run")
@MainActor
struct SetupModelFirstRunTests {
    @Test func nothingIsClaimedBeforeTheFirstLookHasEnded() throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        #expect(mac.model.snapshot == nil)
        #expect(!mac.model.needsFirstRunChoice, "a window that has not looked must not claim a first run")
        #expect(!mac.model.configIsThere, "and must not offer what acts on a config")
        #expect(mac.model.summary.state == .checking)
        #expect(mac.model.statusTitle == .appChecking && mac.model.attentionCount == 0)
        #expect(mac.model.menuState == .loading)
    }

    @Test func aMacWithNoConfigIsOnItsFirstRunAfterTheLook() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        #expect(mac.model.needsFirstRunChoice && !mac.model.configIsThere)
        let offer = try #require(mac.model.offer)
        #expect(offer.terminals.map(\.id) == ["ghostty", "terminal"])
        #expect(mac.model.selectedTerminal == "ghostty" && mac.model.selectedEditor == "vscode", "the choices start from what the Mac has")
        #expect(mac.model.statusTitle == .appSetupTitle && mac.model.attentionCount == 0, "missing setup pieces are expected before setup")
        #expect(mac.model.menuState == .needsSetup, "a default menu is not presented as the person's configured menu")
    }

    @Test func theChoicesStayThePersonsThroughEveryRefresh() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        mac.model.selectedTerminal = "terminal"
        mac.model.selectedAgents = ["codex"]
        await mac.model.refresh()
        #expect(mac.model.selectedTerminal == "terminal" && mac.model.selectedAgents == ["codex"])
    }

    @Test func theSetUpActionFromChecksReturnsToTheChooserWithoutWritingAnything() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        mac.model.select(.checks)
        await mac.model.perform(.setup)
        #expect(mac.model.selectedTab == .overview)
        #expect(!mac.configExists && mac.model.setupAttempt == 0)
    }

    @Test func aMenuWithConfigErrorsIsDistinguishedFromAnIntentionallyEmptyMenu() throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        var snapshot = SetupSnapshot(configFile: mac.paths.configFile, home: mac.home)
        mac.model.apply(snapshot)
        #expect(mac.model.menuState == .empty)
        snapshot.configProblems = ConfigParser.parse("[general\n").diagnostics
        mac.model.apply(snapshot)
        #expect(mac.model.menuState == .invalidConfig)
        snapshot.configProblems = []
        snapshot.menu = MenuPreview.folderMenu(ConfigParser.parse(""), facts: FakeSystemFacts(homeDirectory: mac.home, directories: [mac.home.path]),
                                             folder: mac.home, localizer: .english)
        mac.model.apply(snapshot)
        #expect(mac.model.menuState == .ready)
    }

    @Test func dismissingAnErrorClearsOnlyTheMessage() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        await mac.model.openConfig()
        #expect(mac.model.notice?.isProblem == true)
        let checks = mac.model.checks
        mac.model.dismissNotice()
        #expect(mac.model.notice == nil && mac.model.checks == checks)
        #expect(mac.model.needsFirstRunChoice && !mac.configExists)
    }

    @Test func installOrRepairAndOpenConfigNeverMakeTheConfigBeforeOrDuringTheFirstRun() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        // Before the first look has ended (the window is on screen while the login shell is asked), and then on the first run itself.
        for _ in 0..<2 {
            await mac.model.repair()
            await mac.model.openConfig()
            #expect(!mac.configExists, "a config was made from what was found, and the choice the first run asks for was skipped")
            #expect(mac.model.notice?.isProblem == true)
            #expect(!mac.runner.calls.contains { $0.executable == "/usr/bin/open" }, "an editor was asked to open a file that is not there")
            await mac.model.refresh()
        }
        #expect(mac.model.needsFirstRunChoice, "the chooser is still what the window shows")
    }

    @Test func setUpMakesTheConfigFromTheChoicesAndTheChooserGoes() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        mac.model.selectedTerminal = "terminal"
        mac.model.selectedEditor = "vscode"
        mac.model.selectedAgents = ["claude"]
        await mac.model.setUp()
        let config = ConfigStore.load(paths: mac.paths).config
        #expect(mac.configExists && config.terminal == "terminal" && config.editor == "vscode" && config.enabledAgents == ["claude"])
        #expect(!mac.model.needsFirstRunChoice && mac.model.configIsThere)
        #expect(mac.model.setupReport?.step(.config)?.outcome == .created)
        #expect(mac.model.setupAttempt == 1)
        #expect(!mac.model.isWorking && !mac.model.isSettingUp, "the buttons are on again once the state has been read")
    }

    @Test func aSecondPressWhileTheFirstRunsStartsNothing() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        async let first: Void = mac.model.setUp()
        async let second: Void = mac.model.setUp()
        _ = await (first, second)
        #expect(mac.model.setupAttempt == 1, "the whole setup ran twice")
        #expect(mac.model.setupReport?.step(.config)?.outcome == .created, "and the second run found a config the first had made")
    }

    @Test func aSetUpThatDoesNotComeOutLeavesTheChooserAndTheAnswerForTheWindowToShow() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        // A file where the config folder goes: the config cannot be made, the other steps are.
        try FileManager.default.createDirectory(at: mac.paths.configDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "in the way".write(to: mac.paths.configDirectory, atomically: true, encoding: .utf8)
        await mac.model.setUp()
        #expect(mac.model.needsFirstRunChoice, "there is still no config, so the chooser stays")
        #expect(mac.model.setupReport?.step(.config)?.outcome == .failed, "and the report is there for the window to show above it")
        #expect(mac.model.notice?.isProblem == true)
        #expect(mac.model.setupAttempt == 1)
    }

    @Test func theButtonsStayOffUntilTheStateHasBeenReadAgain() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        // The chooser is drawn until the read after the setup says there is a config; a button that is on meanwhile starts the whole setup again.
        var readingWhileIdle = false
        let observer = Task { @MainActor in
            while !Task.isCancelled {
                if mac.model.isRefreshing && !mac.model.isWorking { readingWhileIdle = true }
                await Task.yield()
            }
        }
        await mac.model.setUp()
        observer.cancel()
        await observer.value
        #expect(!readingWhileIdle)
    }

    @Test func anAppOnADiskImageSetsNothingUpAndSaysSoBeforeAnythingIsTried() async throws {
        let mac = try Mac(helper: "/Volumes/Right Here 0.3.0/Right Here.app/Contents/Helpers/rh"); defer { mac.cleanUp() }
        #expect(mac.model.locationProblem != nil)
        await mac.model.refresh()
        await mac.model.setUp()
        #expect(!mac.configExists && mac.model.setupAttempt == 0 && !mac.model.isWorking)
        try mac.writeConfig()
        await mac.model.refresh()
        await mac.model.repair()
        #expect(mac.model.setupAttempt == 0, "Install or Repair from a disk image would point the runner script into it")
        #expect(!FileManager.default.fileExists(atPath: Installer(home: mac.home).runnerScript.path))
        let fine = try Mac(); defer { fine.cleanUp() }
        #expect(fine.model.locationProblem == nil)
    }
}

@Suite("The setup window's model: reading the Mac again")
@MainActor
struct SetupModelRefreshTests {
    @Test func comingBackToTheAppReadsAgainOnlyAfterTheFirstLookAndNotWhileSomethingRuns() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refreshOnActivation()
        #expect(mac.runner.calls.isEmpty, "the app's own activation at launch must not start a second look beside the first")
        await mac.model.refresh()
        let after = mac.runner.calls.count
        try mac.writeConfig()
        await mac.model.refreshOnActivation()
        #expect(mac.runner.calls.count > after, "it did not look again")
        #expect(mac.model.configIsThere, "a config made meanwhile, by an AI assistant's setup, is seen")
    }

    @Test func comingBackToTheAppInQuickSuccessReadsOnlyOnce() async throws {
        // Each read starts the person's login shell, which runs their startup files: switching between windows must not run them at every switch.
        let mac = try Mac(activationQuietPeriod: .seconds(60)); defer { mac.cleanUp() }
        await mac.model.refresh()
        let after = mac.runner.calls.count
        for _ in 0..<5 { await mac.model.refreshOnActivation() }
        #expect(mac.runner.calls.count == after, "a read that is seconds old was read again")
        await mac.model.refresh()
        #expect(mac.runner.calls.count > after, "the refresh button always reads")
    }

    @Test func aFailedSetupIsShownUntilTheNextReadOfItsOwnAndNoLonger() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        try FileManager.default.createDirectory(at: mac.paths.configDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "in the way".write(to: mac.paths.configDirectory, atomically: true, encoding: .utf8)
        await mac.model.setUp()
        #expect(mac.model.setupReport?.step(.config)?.outcome == .failed, "the read that the setup ends with must not take its answer away")
        // An AI assistant (or `rh setup` in a terminal) makes the config meanwhile, and the person comes back to the window.
        try FileManager.default.removeItem(at: mac.paths.configDirectory)
        try mac.writeConfig()
        await mac.model.refreshOnActivation()
        #expect(mac.model.configIsThere && !mac.model.needsFirstRunChoice)
        #expect(mac.model.setupReport == nil, "the red mark of a config step that no longer matters stood next to a config that is there")
    }

    @Test func aSetupThatWentWellStaysAsTheListOfWhatItDid() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        await mac.model.setUp()
        let report = try #require(mac.model.setupReport)
        #expect(report.ok)
        let ok = [DoctorCheck(.config, status: .ok), DoctorCheck(.finderExtension, status: .ok)]
        mac.model.apply(SetupSnapshot(checks: ok, configFile: mac.paths.configFile, configExists: true, home: mac.home))
        #expect(mac.model.setupReport == report)
    }

    @Test func theExtensionIsLookedAtOnlyWhileTheWindowCanBeSeenAndTheLookStopsWhenItIsOn() async throws {
        let mac = try Mac(visible: false); defer { mac.cleanUp() }
        try mac.writeConfig()
        await mac.model.refresh()
        #expect(mac.model.summary.extensionNeedsSetup)
        let looksBefore = mac.runner.pluginkitLooks
        let watching = Task { await mac.model.watchExtension() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(mac.runner.pluginkitLooks == looksBefore, "a window nobody can see is not looked after")
        mac.showWindow(true)
        #expect(await mac.eventually { mac.runner.pluginkitLooks > looksBefore }, "it never looked")
        mac.runner.switchExtensionOn()
        #expect(await mac.eventually { !mac.model.summary.extensionNeedsSetup }, "the first-run card is replaced by the status once the switch is on")
        watching.cancel()
        await watching.value
    }

    @Test func theExtensionIsLookedAtAgainAfterItWasOnSoSwitchingItOffIsNoticed() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig()
        mac.runner.switchExtension(on: true)
        await mac.model.refresh()
        #expect(!mac.model.summary.extensionNeedsSetup)
        let watching = Task { await mac.model.watchExtension() }
        defer { watching.cancel() }
        let before = mac.runner.pluginkitLooks
        #expect(await mac.eventually { mac.runner.pluginkitLooks > before }, "once the extension is on nobody looks at it again, so switching it off is never seen")
        mac.runner.switchExtension(on: false)
        #expect(await mac.eventually { mac.model.summary.extensionNeedsSetup }, "the first-run card does not come back by itself when the extension is switched off")
    }

    @Test func aWindowThatIsClosedStopsTheLook() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig()
        await mac.model.refresh()
        let watching = Task { await mac.model.watchExtension() }
        #expect(await mac.eventually { mac.runner.pluginkitLooks > 1 })
        watching.cancel()
        await watching.value
        let looks = mac.runner.pluginkitLooks
        try await Task.sleep(for: .milliseconds(100))
        #expect(mac.runner.pluginkitLooks == looks, "the look went on after the window was closed")
    }
}
