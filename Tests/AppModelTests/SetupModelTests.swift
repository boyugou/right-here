import CryptoKit
import Foundation
import Synchronization
import SwiftUI
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
        var delay: Duration = .zero
        var shellOutput = ""
        /// A second copy of the extension that macOS keeps registered, whatever `pluginkit -r` is told.
        var lastingCopy: String?
    }

    private let state = Mutex(State())
    static let appex = "/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex"

    var calls: [ProcessStep] { state.withLock { $0.calls } }
    var pluginkitLooks: Int { calls.filter { $0.executable == "/usr/bin/pluginkit" && $0.arguments.first == "-m" }.count }
    func switchExtensionOn() { switchExtension(on: true) }
    func switchExtension(on: Bool) { state.withLock { $0.extensionOn = on } }
    /// Every process takes this long to answer, as the login shell and pluginkit do on a real Mac: a read of the whole state takes as long.
    func answerSlowly(_ delay: Duration) { state.withLock { $0.delay = delay } }
    /// What the login shell prints when it is asked about the agents' commands.
    func answerShell(_ output: String) { state.withLock { $0.shellOutput = output } }
    /// Another copy of the extension stays registered: a copy of the app on disk that macOS registers again after each `pluginkit -r`.
    func keepRegistered(_ appex: String) { state.withLock { $0.lastingCopy = appex } }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        let (on, delay, shell, lasting) = state.withLock { state -> (Bool, Duration, String, String?) in
            state.calls.append(step)
            // A setup registers the extension and switches it on (`pluginkit -a`, then `-e use`), as on a real Mac.
            if step.executable == "/usr/bin/pluginkit", step.arguments.starts(with: ["-e", "use"]) { state.extensionOn = true }
            return (state.extensionOn, state.delay, state.shellOutput, state.lastingCopy)
        }
        if delay > .zero { try? await Task.sleep(for: delay) }
        if step.arguments.first == "-lic" { return ProcessResult(status: 0, standardOutput: shell) }
        if step.executable == "/usr/bin/pluginkit", step.arguments.first == "-m", on {
            let line = { (path: String) in "+    \(AppIdentity.extensionBundleID)(0.3.0)\tAAAA\t2026-10-16 07:33:49 +0000\t\(path)\n" }
            return ProcessResult(status: 0, standardOutput: line(Self.appex) + (lasting.map(line) ?? ""))
        }
        return ProcessResult(status: 0)
    }
}

private final class Switch: Sendable {
    private let state: Mutex<(on: Bool, reads: Int)>
    init(_ on: Bool) { state = Mutex((on, 0)) }
    var isOn: Bool { state.withLock { $0.reads += 1; return $0.on } }
    /// How many times it was asked: a loop that asks it each time round has gone round that often.
    var reads: Int { state.withLock { $0.reads } }
    func set(_ on: Bool) { state.withLock { $0.on = on } }
}

/// A Mac of made-up facts with a temporary home, and a window model over it. Nothing outside the home is touched, no process is started.
@MainActor
private struct Mac {
    let home: URL
    let paths: RHPaths
    let runner = ScriptedMac()
    /// The made-up Mac the window and its actions look at.
    let facts: FakeSystemFacts
    let model: SetupModel
    private let visible: Switch

    static let inTheApplicationsFolder = "/Applications/Right Here.app/Contents/Helpers/rh"

    /// `patience` is how long a change waits for the one that is being written. Tests wait long by default: on a machine that runs four suites at once a write
    /// of a moment takes seconds, and a change refused for that would be a failure of the machine, not of the code.
    init(helper: String = Mac.inTheApplicationsFolder, visible: Bool = true, pollInterval: Duration = .milliseconds(10), idleInterval: Duration = .milliseconds(10),
         activationQuietPeriod: Duration = .zero, patience: Duration? = nil, trial: Bool = true, copies: [AppCopy] = []) throws {
        let patience = patience ?? .seconds(30)
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
        var facts = FakeSystemFacts(homeDirectory: home, directories: [home.path], applications: [
            "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
            "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        ])
        if !copies.isEmpty { facts.copies[AppIdentity.hostBundleID] = copies }
        self.facts = facts
        let flag = Switch(visible)
        self.visible = flag
        let loader = SetupLoader(facts: facts, paths: paths, runner: runner, helperPath: helper, localizer: .english)
        // A trial leaves the registration of the Finder extension alone; without one, there is no app here to register, so that step is skipped all the same.
        let actions = SetupActions(facts: facts, paths: paths, runner: runner, helperPath: helper, app: nil, trialHome: trial ? home : nil)
        model = SetupModel(loader: loader, actions: actions, facts: facts, helper: helper, pollInterval: pollInterval, idleInterval: idleInterval,
                           activationQuietPeriod: activationQuietPeriod, patience: patience, windowIsVisible: { flag.isOn })
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }
    func showWindow(_ shown: Bool) { visible.set(shown) }
    var visibilityReads: Int { visible.reads }
    var configExists: Bool { FileManager.default.fileExists(atPath: paths.configFile.path) }

    func writeConfig(_ text: String = "[general]\n") throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try text.write(to: paths.configFile, atomically: true, encoding: .utf8)
    }

    /// Waits, a few milliseconds at a time, for `condition`; a test of a poll cannot know to the millisecond when it has looked.
    func eventually(within limit: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
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
    }

    @Test func aMacWithNoConfigIsOnItsFirstRunAfterTheLook() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        #expect(mac.model.needsFirstRunChoice && !mac.model.configIsThere)
        let offer = try #require(mac.model.offer)
        #expect(offer.terminals.map(\.id) == ["ghostty", "terminal"])
        #expect(mac.model.selectedTerminal == "ghostty" && mac.model.selectedEditor == "vscode", "the choices start from what the Mac has")
    }

    @Test func theChoicesStayThePersonsThroughEveryRefresh() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        mac.model.selectedTerminal = "terminal"
        mac.model.selectedAgents = ["codex"]
        await mac.model.refresh()
        #expect(mac.model.selectedTerminal == "terminal" && mac.model.selectedAgents == ["codex"])
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

@Suite("The setup window's model: what Install or Repair shows while it runs and when it ends")
@MainActor
struct SetupModelRepairFeedbackTests {
    @Test func aRepairSaysWhatItDoesWhileItRunsAndHowItCameOutWhenItEnds() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\nagents = []\n")
        // The installed app's extension is registered, as on a Mac that has the app; a repair here cannot install the app.
        mac.runner.switchExtensionOn()
        await mac.model.refresh()
        mac.runner.answerSlowly(.milliseconds(100))
        let repair = Task { await mac.model.repair() }
        #expect(await mac.eventually { mac.model.setupPhase != nil }, "the window said nothing while the repair ran")
        #expect(mac.model.isRepairing, "the button that was pressed shows that it runs")
        await repair.value
        #expect(mac.model.setupPhase == nil && !mac.model.isWorking && !mac.model.isRepairing)
        #expect(mac.model.check(.finderExtension) != nil, "a trial's repair leaves the extension's row out of its checks; the window reads them itself then")
        let changed = try #require(mac.model.setupReport.map(SetupModel.changedPieces))
        #expect(!changed.isEmpty, "a first repair writes the runner script, the link and the Quick Actions")
        #expect(mac.model.repairOutcome == .repaired(changed: changed.count))
        #expect(mac.model.lastAnnouncement?.hasPrefix(Localizer.system.string(.appRepairDone)) == true, "VoiceOver is told it ended: \(mac.model.lastAnnouncement ?? "nothing")")

        await mac.model.repair()
        #expect(mac.model.repairOutcome == .repaired(changed: 0), "a second repair finds everything in place, and says so")
        mac.model.select(.agents)
        #expect(mac.model.repairOutcome == nil, "what a repair said goes with the page it was pressed on")
    }

    /// A check that still asks for Install or Repair after one ran is named: the button stays the window's main one, and "done" alone read as a press that did nothing.
    @Test func aRepairThatLeavesACheckAskingForItSaysWhichOne() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\nagents = []\n")
        mac.runner.switchExtensionOn()
        mac.runner.keepRegistered("/Users/tester/Downloads/Right Here.app/Contents/PlugIns/FinderExtension.appex")
        await mac.model.refresh()
        #expect(mac.model.repairIsWanted, "two registered copies ask for Install or Repair")
        await mac.model.repair()
        guard case .repairLeft(let titles)? = mac.model.repairOutcome else { Issue.record("\(String(describing: mac.model.repairOutcome))"); return }
        #expect(titles == [mac.model.check(.finderExtension)?.title(in: Localizer.system)].compactMap(\.self))
        #expect(mac.model.repairOutcome?.isProblem == true)
    }

    @Test func aRepairReplacesTheLastNoticeAndSaysItsOwnOnlyOnThePageItWasPressedOn() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\nagents = []\n")
        await mac.model.refresh()
        mac.model.say(.listChanged)
        await mac.model.repair()
        #expect(mac.model.notice == nil, "the refusal of an earlier change stayed in the sidebar after a repair that worked")
        mac.runner.answerSlowly(.milliseconds(100))
        let repair = Task { await mac.model.repair() }
        #expect(await mac.eventually { mac.model.setupPhase != nil })
        mac.model.select(.folders)
        await repair.value
        #expect(mac.model.repairOutcome == nil, "the line under the header is for the page the button was pressed on")
    }

    @Test func aCopyOfTheSameVersionThatIsNotTheOneToKeepSetsNothingUp() async throws {
        // The doctor says to keep one of two copies of one version; the other set everything up for itself and was then moved to the Trash.
        let mac = try Mac(helper: "/Applications/Old/Right Here.app/Contents/Helpers/rh",
                          copies: [AppCopy(path: "/Applications/Right Here.app", version: AppIdentity.version), AppCopy(path: "/Applications/Old/Right Here.app", version: AppIdentity.version)])
        defer { mac.cleanUp() }
        #expect(mac.model.newerCopy?.path == "/Applications/Right Here.app" && !mac.model.canSetUp)
        let kept = try Mac(copies: [AppCopy(path: "/Applications/Right Here.app", version: AppIdentity.version), AppCopy(path: "/Applications/Old/Right Here.app", version: AppIdentity.version)])
        defer { kept.cleanUp() }
        #expect(kept.model.newerCopy == nil && kept.model.canSetUp, "the copy to keep sets up")
    }

    @Test func aCopyThatIsTrashedOrInstalledWhileTheWindowIsOpenIsSeenAtTheNextRead() async throws {
        let mac = try Mac(helper: "/Applications/Old/Right Here.app/Contents/Helpers/rh",
                          copies: [AppCopy(path: "/Applications/Right Here.app", version: "99.0"), AppCopy(path: "/Applications/Old/Right Here.app", version: AppIdentity.version)])
        defer { mac.cleanUp() }
        #expect(!mac.model.canSetUp)
        // The newer copy was moved to the Trash: the next read finds only this one, which may set Right Here up again.
        mac.model.apply(SetupSnapshot(configFile: mac.paths.configFile, home: mac.home, installedCopies: [AppCopy(path: "/Applications/Old/Right Here.app", version: AppIdentity.version)]))
        #expect(mac.model.newerCopy == nil && mac.model.canSetUp && mac.model.otherCopies.isEmpty)
        // And a newer one installed meanwhile is seen the same way.
        mac.model.apply(SetupSnapshot(configFile: mac.paths.configFile, home: mac.home, installedCopies: [AppCopy(path: "/Applications/Right Here.app", version: "99.1"), AppCopy(path: "/Applications/Old/Right Here.app", version: AppIdentity.version)]))
        #expect(mac.model.newerCopy?.version == "99.1" && !mac.model.canSetUp)
    }

    @Test func anOlderCopySetsNothingUpWhileANewerOneIsInstalled() async throws {
        // A person opened 0.3.2 by mistake and pressed Install or Repair: the runner script, the Quick Actions and the Finder extension then ran the old rh.
        let mac = try Mac(helper: "/Users/tester/Applications/Right Here.app/Contents/Helpers/rh",
                          copies: [AppCopy(path: "/Applications/Right Here.app", version: "99.0"), AppCopy(path: "/Users/tester/Applications/Right Here.app", version: "0.3.2")])
        defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        await mac.model.refresh()
        #expect(!mac.model.canSetUp)
        await mac.model.repair()
        #expect(mac.model.setupAttempt == 0 && !FileManager.default.fileExists(atPath: Installer(home: mac.home).runnerScript.path))
    }

    @Test func anOlderCopyDoesNotRewriteTheQuickActionsToRunItsOwnRh() async throws {
        let mac = try Mac(helper: "/Users/tester/Applications/Right Here.app/Contents/Helpers/rh",
                          copies: [AppCopy(path: "/Applications/Right Here.app", version: "99.0"), AppCopy(path: "/Users/tester/Applications/Right Here.app", version: "0.3.2")])
        defer { mac.cleanUp() }
        #expect(mac.model.newerCopy != nil)
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        // The Quick Actions the newer copy made.
        _ = await SetupActions(facts: mac.facts, paths: mac.paths, runner: mac.runner, helperPath: "/Applications/Right Here.app/Contents/Helpers/rh",
                               trialHome: mac.home).repair()
        await mac.model.refresh()
        let before = Installer(home: mac.home).installedServices()
        #expect(!before.isEmpty)
        #expect(mac.model.check(.services)?.status == .ok, "what the newer copy made is what the config asks for")
        #expect(await mac.model.addChoice(.quickActions, "copy-path.name"))
        #expect(Installer(home: mac.home).installedServices() == before, "the old copy wrote the Quick Actions to run its own rh")
        #expect(mac.model.check(.services)?.status == .warn, "they were not written again, and the window says at once that they differ from the config")
    }

    @Test func theFirstRunHasNoBadgeAndInstallOrRepairIsTheMainButtonOnlyWhenACheckAsksForIt() async throws {
        // On the first run the checks find what Set Up makes: a badge of 5 said something was wrong before the person had done anything.
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        #expect(mac.model.needsFirstRunChoice && SetupTab.allCases.allSatisfy { mac.model.badge(for: $0) == nil })
        #expect(!mac.model.repairIsWanted)
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\nagents = []\n")
        await mac.model.refresh()
        #expect(mac.model.repairIsWanted, "nothing is installed yet: the runner script's check says to press Install or Repair")
        mac.runner.switchExtensionOn()
        await mac.model.repair()
        #expect(!mac.model.checks.contains { $0.id == .finderRunner && $0.status != .ok })
        #expect(!mac.model.repairIsWanted, "after a repair nothing asks for it, and the step that is next keeps the main button: \(mac.model.checks.filter { $0.fix != nil }.map { "\($0.id.rawValue) \($0.fix?.key.rawValue ?? "")" })")
    }

    @Test func whatACopyButtonSaidGoesWithItsPage() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        mac.model.select(.ai)
        mac.model.say(.promptCopied)
        mac.model.select(.agents)
        #expect(mac.model.notice == nil)
        mac.model.say(.listChanged)
        mac.model.select(.folders)
        #expect(mac.model.notice == .listChanged, "a notice of something else stays")
    }

    @Test func aRepairThatFailsSaysWhyUnderTheHeader() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        // No config: Install or Repair refuses, and says so where the button is.
        await mac.model.refresh()
        await mac.model.repair()
        #expect(mac.model.repairOutcome?.isProblem == true)
    }

    @Test func theChecksARepairRanAreShownAndNotRunAgain() async throws {
        // The doctor starts the login shell and takes seconds; reading the Mac again after a repair ran it a second time, and the person waited through both.
        let mac = try Mac(trial: false); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\nagents = []\n")
        await mac.model.refresh()
        let before = mac.runner.pluginkitLooks
        await mac.model.repair()
        #expect(mac.runner.pluginkitLooks - before == 1, "the extension was looked at \(mac.runner.pluginkitLooks - before) times: the checks ran more than once")
        #expect(mac.model.check(.finderExtension) != nil && mac.model.check(.finderRunner)?.status == .ok, "the window shows the checks the repair ran")
    }
}

@Suite("The setup window's model: an older copy of the app")
@MainActor
struct SetupModelOlderCopyTests {
    @Test func anOldCopyKnowsTheNewerOneThatIsInstalledAndTheNewestKnowsNone() throws {
        let old = try Mac(helper: "/Users/tester/Applications/Right Here.app/Contents/Helpers/rh", copies: [
            AppCopy(path: "/Users/tester/Applications/Right Here.app", version: "0.3.2"), AppCopy(path: "/Applications/Right Here.app", version: "99.0")])
        defer { old.cleanUp() }
        #expect(old.model.newerCopy?.path == "/Applications/Right Here.app")
        #expect(old.model.runningCopy == AppCopy(path: "/Users/tester/Applications/Right Here.app", version: AppIdentity.version))
        let newest = try Mac(copies: [AppCopy(path: "/Applications/Right Here.app", version: AppIdentity.version), AppCopy(path: "/Applications/Old/Right Here.app", version: "0.3.2")])
        defer { newest.cleanUp() }
        #expect(newest.model.newerCopy == nil)
        #expect(newest.model.otherCopies.map(\.path) == ["/Applications/Old/Right Here.app"], "the copies the check says to move to the Trash, which its button shows")
    }
}

@Suite("The setup window's model: how long a change waits")
@MainActor
struct SetupModelPatienceTests {
    @Test func theWindowsOwnChangeWaitsLongerThanAWriteOfTheConfigTakesOnABusyMac() throws {
        // The tests give each window their own patience, so the window's own is held here: at least a second, which a write of the config with its lock and its history stays under.
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let facts = FakeSystemFacts(homeDirectory: home)
        let paths = RHPaths(environment: [:], home: home)
        let model = SetupModel(loader: SetupLoader(facts: facts, paths: paths, runner: FakeProcessRunner(), helperPath: Mac.inTheApplicationsFolder),
                               actions: SetupActions(facts: facts, paths: paths, runner: FakeProcessRunner(), helperPath: Mac.inTheApplicationsFolder, trialHome: home),
                               facts: facts, helper: Mac.inTheApplicationsFolder, windowIsVisible: { false })
        #expect(model.patience >= .seconds(1), "\(model.patience)")
    }
}

@Suite("The setup window's model: the language")
@MainActor
struct SetupModelLanguageTests {
    @Test func choosingALanguageWritesItAndTheWindowIsInItAtOnce() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\n")
        await mac.model.refresh()
        #expect(mac.model.localizer == .system)
        await mac.model.setLanguage("ar")
        #expect(try String(contentsOf: mac.paths.configFile, encoding: .utf8).contains("language = \"ar\""))
        #expect(mac.model.localizer.resolvedLanguage == "ar" && mac.model.localizer.isRightToLeft, "the window is written, and laid out, in the language before the next full read")
        #expect(mac.model.configEdit?.message == .appEditSaved)
        await mac.model.setLanguage(nil)
        #expect(mac.model.snapshot?.language == nil && mac.model.localizer == .system)
        #expect(try !String(contentsOf: mac.paths.configFile, encoding: .utf8).contains("language"))
        await mac.model.setLanguage("klingon")
        #expect(mac.model.snapshot?.language == nil, "a language the app does not have is not written")
    }
}

@Suite("The setup window's model: whether a terminal would find each agent")
@MainActor
struct SetupModelAgentCommandTests {
    @Test func eachAgentSaysWhetherTheLoginShellFindsItsCommandAndWhere() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        mac.runner.answerShell("\nclaude\u{01}\(mac.home.path)/.local/bin/claude\n\ngemini\u{01}/opt/homebrew/bin/gemini\n\nkimi\u{01}kimi\n\u{01}rh-done\u{01}\n")
        await mac.model.refresh()
        let agents = try #require(mac.model.general?.agents)
        func state(_ id: String) -> AgentCommandState? { agents.first { $0.id == id }.flatMap(mac.model.commandState(of:)) }
        #expect(state("claude") == .found(path: "~/.local/bin/claude"), "a path in the home is written from ~")
        #expect(state("gemini") == .found(path: "/opt/homebrew/bin/gemini"), "an agent that is not in the menu is looked up too")
        #expect(state("kimi") == .found(path: nil), "an alias or a function has no path to show")
        #expect(state("codex") == .missing)

        mac.runner.answerShell("\nclaude\u{01}/opt/claude\n")
        await mac.model.refresh()
        let again = try #require(mac.model.general?.agents.first { $0.id == "codex" })
        #expect(mac.model.commandState(of: again) == .unknown, "a shell that did not get to the end does not say an agent is missing")
    }

    @Test func theAgentsOutOfTheMenuAreTheFoundOnesFirstAndTheMissingOnesApart() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        mac.runner.answerShell("\nclaude\u{01}/opt/claude\n\nkimi\u{01}kimi\n\u{01}rh-done\u{01}\n")
        await mac.model.refresh()
        let general = try #require(mac.model.general)
        let (others, missing) = mac.model.agentsOutOfMenu(general)
        #expect(others.map(\.id) == ["kimi"], "the one the shell has, and not the one already in the menu")
        #expect(!missing.isEmpty && missing.allSatisfy { mac.model.commandState(of: $0) == .missing })
        #expect(Set(others.map(\.id) + missing.map(\.id)) == Set(general.agents.filter { !$0.enabled }.map(\.id)), "every agent out of the menu is listed once")
        #expect(!mac.model.listsMissingAgentsAtFirst(general), "with an agent found, the ones not found start as a folded line")

        mac.runner.answerShell("\nclaude\u{01}/opt/claude\n")
        await mac.model.refresh()
        let unanswered = mac.model.agentsOutOfMenu(try #require(mac.model.general))
        #expect(unanswered.missing.isEmpty, "a shell that did not get to the end says no agent is missing")

        mac.runner.answerShell("\n\u{01}rh-done\u{01}\n")
        await mac.model.refresh()
        #expect(mac.model.listsMissingAgentsAtFirst(try #require(mac.model.general)), "with none found, the ones to install are what the page offers")
        #expect(unanswered.others.count == general.agents.filter { !$0.enabled }.count)
    }

    @Test func nothingIsSaidOfAnAgentBeforeTheShellWasAsked() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nagents = [\"claude\"]\n")
        await mac.model.refresh()
        #expect(await mac.model.createAgent(name: "Lazygit", command: "lazygit"))
        let added = try #require(mac.model.general?.agents.first { $0.command == "lazygit" })
        #expect(mac.model.commandState(of: added) == nil, "an agent added after the checks ran was not asked about")
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
        let readsBefore = mac.visibilityReads
        let watching = Task { await mac.model.watchExtension() }
        // A loaded machine may not run the loop at all within a fixed wait, and no look would then say nothing: it is waited for until it has gone round a few times.
        // A minute: under the load of every suite at once the main actor can be busy for many seconds, and this only has to wait for the loop to run.
        #expect(await mac.eventually(within: .seconds(60)) { mac.visibilityReads >= readsBefore + 3 }, "the loop never asked whether the window can be seen")
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

@Suite("The setup window's model: editing the Finder menu")
@MainActor
struct SetupModelMenuEditingTests {
    private static let listed = "[menu]\nitems = [\"open-terminal\", \"open-editor\", \"-\", \"copy-path\", \"new-file\"]\n"

    private func text(_ mac: Mac, _ file: URL? = nil) -> String {
        (try? String(contentsOf: file ?? mac.paths.configFile, encoding: .utf8)) ?? ""
    }

    private func entries(_ mac: Mac) -> [String] { mac.model.menuEditor?.rows.map(\.entry) ?? [] }

    @Test func aMacWithAConfigHasAMenuToEditAndOneWithoutDoesNot() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        #expect(mac.model.menuEditor == nil)
        mac.model.setEditingMenu(true)
        #expect(!mac.model.isEditingMenu, "there is nothing to edit before the first run has made a config")
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        #expect(entries(mac) == ["open-terminal", "open-editor", "-", "copy-path", "new-file"])
        #expect(mac.model.menuEditor?.usesDefaults == false && !mac.model.menuIsMachineOwn)
        mac.model.setEditingMenu(true)
        #expect(mac.model.isEditingMenu)
        mac.model.setEditingMenu(false)
        #expect(!mac.model.isEditingMenu && mac.model.configEdit == nil)
    }

    @Test func aConfigWithAnErrorCannotBeEdited() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"nonsense\"\n" + Self.listed)
        await mac.model.refresh()
        #expect(mac.model.menuEditor == nil)
        await mac.model.removeMenuRow(1)
        #expect(text(mac).contains("open-terminal") && mac.model.configEdit == nil)
    }

    @Test func aDragWritesTheListAndTheRowsFollow() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        mac.model.beginDrag(row: 4, token: "4:copy-path", scope: "menu")
        let asked = mac.runner.calls.count
        await mac.model.moveMenuRows(from: IndexSet(integer: 3), to: 0)
        #expect(mac.runner.calls.count == asked, "an edit shows at once: the doctor, which starts the login shell, is not asked again")
        #expect(text(mac) == "[menu]\nitems = [\"copy-path\", \"open-terminal\", \"open-editor\", \"-\", \"new-file\"]\n")
        #expect(entries(mac) == ["copy-path", "open-terminal", "open-editor", "-", "new-file"])
        #expect(mac.model.configEdit?.message == .appMenuEditedMoved("Copy Path") && mac.model.configEdit?.key == "menu.items" && mac.model.configEdit?.tab == .menu)
        #expect(mac.model.configEdit?.digest == SHA256.hash(data: Data(text(mac).utf8)).map { String(format: "%02x", $0) }.joined(), "the note says which text the change wrote")
        #expect(mac.model.drag == nil && !mac.model.isWorking && mac.model.notice == nil)
        #expect(mac.model.menuRows.first?.title == "Copy Path", "the preview shows the new order")
    }

    @Test func aDragEndsWhereSwiftUIWouldPutTheRow() async throws {
        // The editor takes `onMove`'s two numbers as they are: every drag of one row, against what the framework does to an array.
        let items = ["open-terminal", "open-editor", "-", "copy-path", "new-file"]
        for from in 0..<items.count {
            for destination in 0...items.count {
                let mac = try Mac(); defer { mac.cleanUp() }
                try mac.writeConfig(Self.listed)
                await mac.model.refresh()
                await mac.model.moveMenuRows(from: IndexSet(integer: from), to: destination)
                var expected = items
                expected.move(fromOffsets: IndexSet(integer: from), toOffset: destination)
                #expect(entries(mac) == expected, "row \(from) to \(destination)")
            }
        }
    }

    @Test func aDragThatLeavesTheRowWhereItIsWritesNothing() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        await mac.model.moveMenuRows(from: IndexSet(integer: 2), to: 2)
        await mac.model.moveMenuRows(from: IndexSet(integer: 2), to: 3)
        #expect(text(mac) == Self.listed && mac.model.configEdit == nil)
        #expect(!FileManager.default.fileExists(atPath: mac.paths.historyDirectory.path))
    }

    @Test func theKeyboardAndVoiceOverMoveARowUpAndDown() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        await mac.model.moveMenuRow(2, by: -1)
        #expect(entries(mac) == ["open-editor", "open-terminal", "-", "copy-path", "new-file"])
        await mac.model.moveMenuRow(2, by: 1)
        #expect(entries(mac) == ["open-editor", "-", "open-terminal", "copy-path", "new-file"])
        await mac.model.moveMenuRow(1, by: -1)
        await mac.model.moveMenuRow(5, by: 1)
        await mac.model.moveMenuRow(9, by: -1)
        #expect(entries(mac) == ["open-editor", "-", "open-terminal", "copy-path", "new-file"], "past the ends, or no such row: nothing happens")
    }

    @Test func aRowIsRemovedAndAddedBack() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        await mac.model.removeMenuRow(4)
        #expect(entries(mac) == ["open-terminal", "open-editor", "-", "new-file"])
        #expect(mac.model.configEdit?.message == .appMenuEditedRemoved("Copy Path"))
        #expect(mac.model.menuEditor?.choices.contains { $0.entry == "copy-path" } == true, "what was taken out can be added again")
        await mac.model.addMenuItem("copy-path", at: 1)
        #expect(entries(mac) == ["copy-path", "open-terminal", "open-editor", "-", "new-file"])
        #expect(mac.model.configEdit?.message == .appMenuEditedAdded("Copy Path"))
        await mac.model.addMenuItem("-")
        #expect(entries(mac).last == "-" && mac.model.configEdit?.message == .appMenuEditedAdded(mac.model.localizer.string(.appMenuSeparator)), "the separator is named in the window's language")
    }

    @Test func theFirstChangeOfTheDefaultMenuWritesTheList() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\n")
        await mac.model.refresh()
        #expect(mac.model.menuEditor?.usesDefaults == true)
        await mac.model.removeMenuRow(2)
        var expected = MenuBuilder.defaultItems
        expected.remove(at: 1)
        #expect(entries(mac) == expected && mac.model.menuEditor?.usesDefaults == false)
        #expect(text(mac).hasPrefix("[general]\nterminal = \"ghostty\"\n"), "what was there stays")
        // The list is long, so it is laid out a line to an item.
        #expect(text(mac).hasSuffix("[menu]\nitems = [\n    \"open-terminal\",\n    \"open-with\",\n    \"agents\",\n    \"agents-more\",\n    \"-\",\n    \"new-file\",\n    \"copy-path\",\n]\n"), "\(text(mac))")
    }

    @Test func aChangeIsTakenBackAndTheTextIsTheOneBefore() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        await mac.model.removeMenuRow(1)
        await mac.model.moveMenuRows(from: IndexSet(integer: 0), to: 3)
        #expect(text(mac) != Self.listed)
        // The banner takes back the change it names, and its note goes with it.
        await mac.model.undoEdit()
        #expect(mac.model.configEdit == nil && mac.model.notice == nil)
        #expect(entries(mac) == ["open-editor", "-", "copy-path", "new-file"].filter { $0 != "" } || entries(mac).count == 4, "the move is gone, the removal is not: \(entries(mac))")
        await mac.model.undoEdit()
        #expect(entries(mac).count == 4, "there is no banner any more, so there is nothing for it to take back")
        // The Config page's list of recent changes takes back the last change whoever made it.
        await mac.model.undoConfigChange()
        #expect(text(mac) == Self.listed && mac.model.notice == nil)
        #expect(entries(mac) == ["open-terminal", "open-editor", "-", "copy-path", "new-file"])
        await mac.model.undoConfigChange()
        #expect(mac.model.notice?.isProblem == true, "there is nothing left to take back, and it is said")
    }

    @Test func aFileChangedByHandIsNotUndoneOverTheChange() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        await mac.model.removeMenuRow(1)
        let edited = text(mac) + "# by hand\n"
        try edited.write(to: mac.paths.configFile, atomically: true, encoding: .utf8)
        await mac.model.undoEdit()
        #expect(text(mac) == edited && mac.model.notice?.isProblem == true)
    }

    @Test func aChangeThatTheConfigRefusesIsSaidAndTheFileIsLeftAlone() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        // Somebody breaks the file after the window read it.
        try "[menu\n".write(to: mac.paths.configFile, atomically: true, encoding: .utf8)
        await mac.model.removeMenuRow(1)
        #expect(text(mac) == "[menu\n")
        #expect(mac.model.notice?.isProblem == true && mac.model.configEdit == nil && !mac.model.isWorking)
    }

    @Test func theMachinesOwnFileIsEditedWhenItListsTheMenu() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        try "[menu]\nitems = [\"copy-path\", \"-\", \"open-editor\"]\n".write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8)
        await mac.model.refresh()
        #expect(mac.model.menuIsMachineOwn && entries(mac) == ["copy-path", "-", "open-editor"])
        await mac.model.removeMenuRow(2)
        #expect(text(mac) == Self.listed, "the shared file is not what decides here")
        #expect(text(mac, mac.paths.localConfigFile) == "[menu]\nitems = [\"copy-path\", \"open-editor\"]\n")
        #expect(entries(mac) == ["copy-path", "open-editor"])
    }

    @Test func aSecondChangeThatArrivesWithTheFirstIsIgnoredAndNeverActsOnAStaleList() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        // Two drops that arrive together were each worked out from the list as it is now. One is made; the other would act on places that have moved, so it is ignored.
        async let first: Void = mac.model.moveMenuRows(from: IndexSet(integer: 4), to: 0)
        async let second: Void = mac.model.moveMenuRows(from: IndexSet(integer: 0), to: 5)
        _ = await (first, second)
        let result = entries(mac)
        #expect(result == ["new-file", "open-terminal", "open-editor", "-", "copy-path"] || result == ["open-editor", "-", "copy-path", "new-file", "open-terminal"], "\(result)")
        #expect(ConfigService(paths: mac.paths).history().count == 1, "one change was made")
        #expect(mac.model.notice == nil && mac.model.editRefusal == nil, "and the other said nothing: it was never sent, which is not the same as being refused")
    }

    @Test func editingEndsWhenTheConfigCanNoLongerBeEdited() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        mac.model.setEditingMenu(true)
        #expect(mac.model.isEditingMenu)
        try "[menu\n".write(to: mac.paths.configFile, atomically: true, encoding: .utf8)
        await mac.model.removeMenuRow(1)
        #expect(!mac.model.isEditingMenu && mac.model.menuEditor == nil, "the rows of a config that does not read are not shown")
        try Self.listed.write(to: mac.paths.configFile, atomically: true, encoding: .utf8)
        await mac.model.refresh()
        #expect(mac.model.menuEditor != nil && !mac.model.isEditingMenu, "and the editor does not open by itself again")
    }

    @Test func iconsOfTheEditorAreReadWithTheMenusOwn() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        let editor = try #require(mac.model.menuEditor)
        #expect(editor.rows.first?.nodes.first?.icon == .app("com.mitchellh.ghostty"))
        #expect(editor.choices.contains { $0.entry == "open-with" })
    }
}

@Suite("The setup window's model: the Config page")
@MainActor
struct SetupModelConfigPageTests {
    private static let sample = "# Mine.\n[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n\n[menu]\nitems = [\"open-terminal\", \"copy-path\"]\n"

    private func text(_ mac: Mac, _ file: URL? = nil) -> String {
        (try? String(contentsOf: file ?? mac.paths.configFile, encoding: .utf8)) ?? ""
    }

    private func service(_ mac: Mac) -> ConfigService { ConfigService(paths: mac.paths, environment: [:]) }

    @Test func thePageReadsTheTextTheHistoryAndTheProposals() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        _ = try service(mac).apply(.set("general.terminal", .string("terminal")), actor: .cli)
        guard case .proposed(let proposal, _) = try service(mac).submit([.set("agent.claude.args", .strings(["-p"]))], actor: .mcp) else { Issue.record("not proposed"); return }
        await mac.model.refresh()
        await mac.model.openConfigPage()
        let page = try #require(mac.model.configPage)
        #expect(mac.model.draftText == text(mac) && page.text?.text == text(mac) && !mac.model.textHasChanges)
        #expect(page.history.map(\.actor) == [.cli] && page.proposals.map(\.id) == [proposal.id])
        #expect(mac.model.badge(for: .config) == .attention(1) && mac.model.proposalsWaiting == 1)
        #expect(mac.model.badge(for: .overview) == nil)
    }

    @Test func approvingAProposalThatSwitchesThePromptsOffIsHeldForTheYesThatNamesTheAgents() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\", \"codex\"]\n")
        guard case .proposed(let proposal, _) = try service(mac).submit([.set("general.bypass_permissions", .boolean(true))], actor: .mcp) else { Issue.record("not proposed"); return }
        await mac.model.refresh()
        await mac.model.openConfigPage()
        let before = text(mac)
        await mac.model.approveProposal(proposal.id)
        let held = try #require(mac.model.pendingLoosening)
        #expect(held.proposal == proposal.id && held.agents.map(\.agent) == ["claude", "codex"] && text(mac) == before, "the alert names each agent and its flag, and nothing was made")
        mac.model.declineLoosening()
        #expect(mac.model.pendingLoosening == nil && text(mac) == before && mac.model.proposalsWaiting == 1, "a no leaves the proposal waiting")
        await mac.model.approveProposal(proposal.id)
        await mac.model.confirmLoosening()
        #expect(text(mac).contains("bypass_permissions = true") && mac.model.proposalsWaiting == 0, "a yes makes it")
        // A proposal that starts nothing without asking is made at once, as before.
        guard case .proposed(let plain, _) = try service(mac).submit([.set("agent.claude.args", .strings(["--verbose"]))], actor: .mcp) else { Issue.record("not proposed"); return }
        await mac.model.refresh()
        await mac.model.openConfigPage()
        await mac.model.approveProposal(plain.id)
        #expect(mac.model.pendingLoosening == nil && text(mac).contains("--verbose"))
    }

    @Test func choosingThePageReadsItWithoutAnyoneAskingFurther() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        mac.model.select(.config)
        #expect(await mac.eventually { mac.model.configPage != nil })
        #expect(mac.model.selectedTab == .config && mac.model.draftText == Self.sample)
    }

    @Test func aMacWithNoConfigHasNothingToEdit() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        await mac.model.refresh()
        await mac.model.openConfigPage()
        #expect(mac.model.configPage?.text == nil && mac.model.configPage?.problem?.contains("rh setup") == true && !mac.model.textHasChanges)
        await mac.model.saveConfigText()
        #expect(!mac.configExists, "a first run is not skipped by a save")
    }

    @Test func theDraftSaysWhatIsWrongWithItAsItIsTypedAndAnErrorCannotBeSaved() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        await mac.model.openConfigPage()
        #expect(mac.model.draftProblems.isEmpty)
        mac.model.draftText = Self.sample + "unknown_key = 1\n"
        #expect(mac.model.textHasChanges && mac.model.draftProblems.map(\.severity) == [.warning])
        mac.model.draftText = Self.sample.replacingOccurrences(of: "ghostty", with: "nonsense")
        #expect(mac.model.draftProblems.first?.severity == .error && mac.model.draftProblems.first?.line == 3)
        await mac.model.saveConfigText()
        #expect(text(mac) == Self.sample, "a text that does not read is not written")
        #expect(mac.model.notice?.isProblem == true && mac.model.draftText.contains("nonsense") && mac.model.textHasChanges, "and what was typed is still there")
    }

    @Test func aSavedTextIsTheFilesAndTheMenuFollowsAndTheChangeCanBeTakenBack() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        await mac.model.openConfigPage()
        let asked = mac.runner.calls.count
        mac.model.draftText = "# Mine, changed.\n[menu]\nitems = [\"copy-path\", \"-\", \"open-terminal\"]\n"
        await mac.model.saveConfigText()
        #expect(text(mac) == "# Mine, changed.\n[menu]\nitems = [\"copy-path\", \"-\", \"open-terminal\"]\n")
        #expect(!mac.model.textHasChanges && mac.model.notice == nil)
        #expect(mac.model.configPage?.history.map(\.actor) == [.window])
        #expect(mac.model.menuEditor?.rows.map(\.entry) == ["copy-path", "-", "open-terminal"], "the menu editor and the preview follow the text")
        #expect(mac.runner.calls.count == asked, "and without asking the doctor")
        await mac.model.undoConfigChange()
        #expect(text(mac) == Self.sample && mac.model.draftText == Self.sample && mac.model.configPage?.history.isEmpty == true)
    }

    @Test func aTextIsNotSavedOverAChangeMadeWhileItWasBeingEdited() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        await mac.model.openConfigPage()
        mac.model.draftText = Self.sample + "# my note\n"
        _ = try service(mac).apply(.insert("new-file", into: "menu.items"), actor: .mcp)
        await mac.model.saveConfigText()
        #expect(mac.model.notice?.isProblem == true)
        #expect(text(mac).contains("new-file") && !text(mac).contains("my note"), "the change made meanwhile is still there")
        #expect(mac.model.draftText.hasSuffix("# my note\n") && mac.model.textHasChanges, "and what was typed is kept")
        #expect(mac.model.configPage?.text?.text == Self.sample && mac.model.configPage?.fileMovedUnderDraft == true, "the page holds the text the draft started from, so that a second save is refused too")
        await mac.model.revertConfigText()
        #expect(mac.model.draftText == text(mac) && !mac.model.textHasChanges && mac.model.configPage?.fileMovedUnderDraft == false)
    }

    @Test func revertingThrowsTheTypedTextAway() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        await mac.model.openConfigPage()
        mac.model.draftText = "something else"
        await mac.model.revertConfigText()
        #expect(mac.model.draftText == Self.sample && !mac.model.textHasChanges)
    }

    @Test func theMachinesOwnFileIsEditedAsTextToo() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        await mac.model.openConfigPage()
        mac.model.draftText = "# not saved\n"
        await mac.model.chooseConfigFile(.local)
        #expect(mac.model.configTarget == .shared && mac.model.draftText == "# not saved\n", "text that is not saved is not thrown away by switching")
        await mac.model.revertConfigText()
        await mac.model.chooseConfigFile(.local)
        #expect(mac.model.configTarget == .local && mac.model.draftText == "" && mac.model.configPage?.text?.exists == false)
        mac.model.draftText = "[general]\nterminal = \"terminal\"\n"
        await mac.model.saveConfigText()
        #expect(text(mac, mac.paths.localConfigFile) == "[general]\nterminal = \"terminal\"\n" && text(mac) == Self.sample)
        #expect(mac.model.configPage?.history.map(\.actor) == [.window])
        await mac.model.chooseConfigFile(.shared)
        #expect(mac.model.configTarget == .shared && mac.model.draftText == Self.sample)
    }

    @Test func aProposalIsAppliedByThePersonOrDismissed() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        guard case .proposed(let first, _) = try service(mac).submit([.set("agent.claude.args", .strings(["-p"]))], actor: .mcp),
              case .proposed(let second, _) = try service(mac).submit([.set("agent.claude.command", .string("/tmp/other"))], actor: .mcp) else { Issue.record("not proposed"); return }
        await mac.model.refresh()
        await mac.model.openConfigPage()
        #expect(mac.model.proposalsWaiting == 2)
        await mac.model.approveProposal(first.id)
        #expect(text(mac).contains("args = [\"-p\"]") && mac.model.proposalsWaiting == 1 && mac.model.badge(for: .config) == .attention(1))
        #expect(mac.model.configPage?.history.map(\.actor) == [.window], "the person made it")
        #expect(mac.model.draftText == text(mac), "the editor shows the file with the change")
        await mac.model.dismissProposal(second.id)
        #expect(!text(mac).contains("/tmp/other") && mac.model.proposalsWaiting == 0 && mac.model.badge(for: .config) == nil)
        await mac.model.approveProposal(second.id)
        #expect(mac.model.notice?.isProblem == true, "a proposal that is not there is said")
    }

    @Test func aReadOfTheWholeStateKeepsWhatWasTypedAndShowsWhatChangedMeanwhile() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        mac.model.select(.config)
        #expect(await mac.eventually { mac.model.configPage != nil })
        mac.model.draftText = "typed, not saved"
        guard case .proposed = try service(mac).submit([.set("agent.claude.args", .strings(["-p"]))], actor: .mcp) else { Issue.record("not proposed"); return }
        await mac.model.refresh()
        #expect(await mac.eventually { mac.model.configPage?.proposals.count == 1 }, "a proposal made while the window was open shows when it is read again")
        #expect(mac.model.draftText == "typed, not saved")
        #expect(mac.model.badge(for: .config) == .attention(1))
    }
}

@Suite("The setup window's model: what the person typed and changed is not lost to something else")
@MainActor
struct SetupModelSafetyTests {
    private static let sample = "# Mine.\n[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n\n[menu]\nitems = [\"open-terminal\", \"copy-path\"]\n"
    private static let listed = "[menu]\nitems = [\"open-terminal\", \"open-editor\", \"-\", \"copy-path\", \"new-file\"]\n"

    private func text(_ mac: Mac, _ file: URL? = nil) -> String {
        (try? String(contentsOf: file ?? mac.paths.configFile, encoding: .utf8)) ?? ""
    }

    private func service(_ mac: Mac) -> ConfigService { ConfigService(paths: mac.paths, environment: [:]) }
    private func entries(_ mac: Mac) -> [String] { mac.model.menuEditor?.rows.map(\.entry) ?? [] }

    private func openPage(_ mac: Mac) async {
        mac.model.select(.config)
        _ = await mac.eventually { mac.model.configPage != nil }
    }

    // MARK: The text in the Config editor

    @Test func typedTextSurvivesGoingToAnotherSectionAndBack() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        await openPage(mac)
        let typed = Self.sample + "# typed, not saved\n"
        mac.model.draftText = typed
        mac.model.select(.overview)
        mac.model.select(.config)
        try await Task.sleep(for: .milliseconds(100))
        #expect(mac.model.draftText == typed, "the text that was typed is the person's until they save or revert it")
        #expect(mac.model.textHasChanges)
    }

    @Test func theReviewButtonOfTheOverviewKeepsTheDraftToo() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        _ = try service(mac).submit([.set("agent.claude.args", .strings(["-p"]))], actor: .mcp)
        await mac.model.refresh()
        await openPage(mac)
        let typed = Self.sample + "# typed\n"
        mac.model.draftText = typed
        mac.model.select(.overview)
        mac.model.select(.config)
        try await Task.sleep(for: .milliseconds(100))
        #expect(mac.model.draftText == typed)
    }

    @Test func aMenuEditWhileADraftWaitsKeepsTheDraft() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        await openPage(mac)
        let typed = Self.listed + "# typed\n"
        mac.model.draftText = typed
        mac.model.select(.menu)
        await mac.model.removeMenuRow(1)
        mac.model.select(.config)
        try await Task.sleep(for: .milliseconds(100))
        #expect(mac.model.draftText == typed)
    }

    @Test func aRefreshWhileTypingDoesNotLetASaveOverwriteAChangeMadeMeanwhile() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        await openPage(mac)
        let typed = Self.sample + "# my note\n"
        mac.model.draftText = typed
        // An assistant (or `rh config add` in a terminal) changes the file while the person types, and the person comes back to the window.
        _ = try service(mac).apply(.insert("new-file", into: "menu.items"), actor: .cli)
        await mac.model.refresh()
        _ = await mac.eventually { mac.model.configPage?.fileMovedUnderDraft == true }
        #expect(mac.model.draftText == typed, "what was typed is kept")
        #expect(mac.model.configPage?.fileMovedUnderDraft == true, "and the page says that the file moved")
        await mac.model.saveConfigText()
        #expect(text(mac).contains("new-file") && !text(mac).contains("# my note"), "the change made meanwhile is not overwritten")
        #expect(mac.model.notice?.isProblem == true)
        // A second save is refused as well: the draft still started from the text it started from.
        await mac.model.saveConfigText()
        #expect(text(mac).contains("new-file") && !text(mac).contains("# my note"))
        // Reverting reads the file as it is, and typing on it is saved.
        await mac.model.revertConfigText()
        #expect(mac.model.draftText.contains("new-file") && mac.model.configPage?.fileMovedUnderDraft == false)
    }

    @Test func approvingAProposalWhileTypingIsNotUndoneByASave() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        guard case .proposed(let proposal, _) = try service(mac).submit([.set("agent.claude.args", .strings(["-p"]))], actor: .mcp) else { Issue.record("not proposed"); return }
        await mac.model.refresh()
        await openPage(mac)
        mac.model.draftText = Self.sample + "# my note\n"
        await mac.model.approveProposal(proposal.id)
        #expect(text(mac).contains("args = [\"-p\"]"))
        await mac.model.saveConfigText()
        #expect(text(mac).contains("args = [\"-p\"]"), "the approved change is still there")
        #expect(mac.model.notice?.isProblem == true, "and the save said why it did not happen")
    }

    @Test func applyingAProposalIsAgainstTheFileTheCardShowed() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        guard case .proposed(let proposal, _) = try service(mac).submit([.replaceText(Self.sample + "# from the assistant\n")], actor: .mcp) else { Issue.record("not proposed"); return }
        await mac.model.refresh()
        await openPage(mac)
        let shown = try #require(mac.model.configPage?.proposals.first?.change?.diff)
        #expect(shown.contains("+# from the assistant"))
        // Somebody changes the file after the card was drawn.
        _ = try service(mac).apply(.set("general.terminal", .string("terminal")), actor: .cli)
        let before = text(mac)
        await mac.model.approveProposal(proposal.id)
        #expect(text(mac) == before, "the card's change was not made over a file it never showed")
        #expect(mac.model.notice == .proposalStale)
        let redrawn = try #require(mac.model.configPage?.proposals.first?.change?.diff)
        #expect(redrawn.contains("-terminal = \"terminal\""), "the card shows the change against the file as it is now: \(redrawn)")
        // Looked at again, it is applied.
        await mac.model.approveProposal(proposal.id)
        #expect(text(mac).contains("# from the assistant") && mac.model.notice == nil)
    }

    @Test func aTextPastWhatAConfigMayBeIsAProblemAndIsNotSaved() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        await openPage(mac)
        mac.model.draftText = Self.sample + "# " + String(repeating: "x", count: ConfigParser.maxBytes) + "\n"
        #expect(mac.model.draftProblems.contains { $0.severity == .error }, "the page says so while the text is typed")
        await mac.model.saveConfigText()
        #expect(text(mac) == Self.sample, "nothing was written")
        #expect(mac.model.notice?.isProblem == true)
        #expect(ConfigStore.load(paths: mac.paths).result.diagnostics.allSatisfy { $0.severity != .error })
    }

    @Test func theChecksOfTheDraftAreMadeOnceForEachText() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        await openPage(mac)
        mac.model.draftText = Self.sample + "[general]\nterminal = \"nonsense\"\n"
        let first = mac.model.draftProblems
        #expect(first.contains { $0.severity == .error })
        #expect(mac.model.draftProblems == first)
        mac.model.draftText = Self.sample
        #expect(!mac.model.draftProblems.contains { $0.severity == .error }, "a new text is checked again")
    }

    // MARK: The editors and what happens at the same time

    @Test func aReadThatBeganBeforeAnEditDoesNotPutTheOldRowsBack() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        mac.runner.answerSlowly(.milliseconds(150))
        // The person comes back to the window: a read starts (the config first, then the doctor, which takes the time above).
        let read = Task { await mac.model.refreshOnActivation() }
        _ = await mac.eventually { mac.model.isRefreshing }
        await mac.model.removeMenuRow(4)
        let afterEdit = entries(mac)
        #expect(!afterEdit.contains("copy-path"))
        await read.value
        #expect(entries(mac) == afterEdit, "the read that began before the edit says nothing newer")
        #expect(text(mac).contains("new-file") && !text(mac).contains("copy-path"))
        // The next change acts on what is shown.
        await mac.model.removeMenuRow(4)
        #expect(text(mac).contains("open-terminal") && !text(mac).contains("new-file"), "the fourth row now is New File, and it is what goes")
    }

    @Test func theBannersUndoTakesBackTheChangeItNamesOrNothing() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\n\n" + Self.listed)
        await mac.model.refresh()
        await mac.model.removeMenuRow(4)
        #expect(mac.model.configEdit?.message == .appMenuEditedRemoved("Copy Path") && mac.model.configEdit?.digest != nil)
        // An assistant changes something else afterwards.
        _ = try service(mac).submit([.set("general.terminal", .string("terminal"))], actor: .mcp)
        let before = text(mac)
        await mac.model.undoEdit()
        #expect(text(mac) == before, "neither change was taken back: the last one is not the one the banner names")
        #expect(mac.model.notice == .undoRefused)
        #expect(mac.model.configEdit == nil)
    }

    @Test func theBannersUndoTakesBackTheChangeWhenItIsTheLastOne() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\n\n" + Self.listed)
        await mac.model.refresh()
        await mac.model.removeMenuRow(4)
        await mac.model.undoEdit()
        #expect(text(mac).contains("copy-path") && mac.model.notice == nil)
    }

    @Test func aSaveOnTheConfigPageEndsTheNoteOfAnEarlierChange() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        await mac.model.moveMenuRows(from: IndexSet(integer: 3), to: 0)
        #expect(mac.model.configEdit != nil)
        await openPage(mac)
        mac.model.draftText = text(mac) + "# a note\n"
        await mac.model.saveConfigText()
        #expect(mac.model.configEdit == nil, "an Undo next to it would take back the note, not the move")
    }

    @Test func aMenuEditActsOnTheListTheWindowShowedOrOnNothing() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        _ = try service(mac).apply(.insert("agents", into: "menu.items", at: 1), actor: .cli)
        let before = text(mac)
        await mac.model.removeMenuRow(4)   // what the window shows as Copy Path
        #expect(text(mac) == before, "another item was not removed in its place")
        #expect(mac.model.notice == .listChanged && mac.model.configEdit == nil)
        #expect(entries(mac) == ["agents", "open-terminal", "open-editor", "-", "copy-path", "new-file"], "the window now shows the list as it is")
    }

    @Test func theFirstChangeOfTheDefaultMenuDoesNotOverwriteAListWrittenMeanwhile() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\n")
        await mac.model.refresh()
        #expect(mac.model.menuEditor?.usesDefaults == true)
        _ = try service(mac).submit([.set("menu.items", .strings(["copy-path", "open-terminal"]))], actor: .mcp)
        await mac.model.removeMenuRow(2)
        #expect(text(mac).contains("items = [\"copy-path\", \"open-terminal\"]"), "the assistant's list stays")
        #expect(mac.model.notice == .listChanged)
    }

    @Test func aMenuThatThisMacCutsShortIsNotEditedByPlace() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        let shared = "[menu]\nitems = [\"open-terminal\", \"open.app.zed\", \"copy-path\", \"new-file\"]\n"
        try mac.writeConfig(shared)
        try "disabled = [\"zed\"]\n".write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8)
        await mac.model.refresh()
        #expect(entries(mac) == ["open-terminal", "copy-path", "new-file"] && mac.model.menuEditor?.isExact == false)
        await mac.model.removeMenuRow(2)
        await mac.model.moveMenuRows(from: IndexSet(integer: 2), to: 0)
        #expect(text(mac) == shared, "nothing of the shared file was touched, and the other Mac's Zed entry is still there")
    }

    @Test func aDropOfSomethingTheWindowDidNotPutInTheDragMovesNothing() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig(Self.listed)
        await mac.model.refresh()
        mac.model.beginDrag(row: 4, token: "4:copy-path", scope: "menu")
        #expect(mac.model.endDrag(token: "text from another app", scope: "menu") == nil)
        #expect(mac.model.drag == nil, "the drag is over")
        // A drag that was cancelled leaves its state behind; the next drop of text from anywhere is not the row.
        mac.model.beginDrag(row: 4, token: "4:copy-path", scope: "menu")
        await mac.model.refresh()
        #expect(mac.model.endDrag(token: nil, scope: "menu") == nil)
        mac.model.beginDrag(row: 4, token: "4:copy-path", scope: "menu")
        #expect(mac.model.endDrag(token: "4:copy-path", scope: "menu") == 4, "what the drag carried is the row that was picked up")
        #expect(mac.model.endDrag(token: "4:copy-path", scope: "menu") == nil, "and only once")
    }

    @Test func aRowDroppedOnAnotherListThanTheOneItWasPickedUpInMovesNothing() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        // The Finder menu page has three lists that drag: the rows of the menu, the forms of Copy Path and the Quick Actions.
        mac.model.beginDrag(row: 5, token: "choice:copy_path.styles:5", scope: "choice:copy_path.styles")
        #expect(mac.model.endDrag(token: "choice:copy_path.styles:5", scope: "choice:services.items") == nil, "a form of Copy Path is not a Quick Action")
        #expect(mac.model.drag == nil, "the drag is over")
        mac.model.beginDrag(row: 5, token: "choice:copy_path.styles:5", scope: "choice:copy_path.styles")
        #expect(mac.model.endDrag(token: "choice:copy_path.styles:5", scope: "menu") == nil)
        mac.model.beginDrag(row: 5, token: "choice:copy_path.styles:5", scope: "choice:copy_path.styles")
        #expect(mac.model.endDrag(token: "choice:copy_path.styles:5", scope: "choice:copy_path.styles") == 5, "in its own list it is the row that was picked up")
    }
}

@Suite("The setup window's model: one agent's own options")
@MainActor
struct SetupModelAgentOptionsTests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"

    private func text(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.configFile, encoding: .utf8)) ?? "" }
    private func service(_ mac: Mac) -> ConfigService { ConfigService(paths: mac.paths, environment: [:]) }

    private func started(_ config: String = SetupModelAgentOptionsTests.sample) async throws -> Mac {
        let mac = try Mac()
        try mac.writeConfig(config)
        await mac.model.refresh()
        return mac
    }

    @Test func anOptionIsWrittenToTheConfigShownAgainAndTakenBack() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(mac.model.agentOptions("claude")?.command == "claude")
        await mac.model.setAgentCommand("claude", "  claude --model opus ")
        #expect(text(mac).contains("[agent.claude]\ncommand = \"claude --model opus\"\n"), "\(text(mac))")
        #expect(mac.model.agentOptions("claude")?.command == "claude --model opus", "the page shows what the config says now")
        #expect(mac.model.configEdit?.key == "agent.claude.command" && mac.model.configEdit?.tab == .agents)
        await mac.model.undoEdit()
        #expect(text(mac) == Self.sample && mac.model.agentOptions("claude")?.command == "claude")
    }

    @Test func aChangeMadeWhileAnotherIsBeingWrittenIsNotLost() async throws {
        // A field that loses its focus as the next control is used makes its change while that control's change is made.
        let mac = try await started(); defer { mac.cleanUp() }
        async let command = mac.model.setAgentCommand("claude", "claude --model opus")
        async let launcher = mac.model.setAgentLauncher("claude", .link)
        _ = await (command, launcher)
        let written = text(mac)
        #expect(written.contains("command = \"claude --model opus\"") && written.contains("launcher = \"link\""), "\(written)")
    }

    @Test func startingOneAgentWithoutAskingNeedsTheConfirmationAndAskingAgainDoesNot() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        await mac.model.setAgentBypass("claude", true)
        #expect(text(mac) == Self.sample, "the window never takes the person's yes for granted")
        #expect(mac.model.pendingLoosening?.agents == [PromptEffects.Entry(agent: "claude", name: "Claude Code", flag: "--dangerously-skip-permissions")])
        await mac.model.confirmLoosening()
        #expect(text(mac).contains("bypass_permissions = true") && mac.model.pendingLoosening == nil)
        await mac.model.setAgentBypass("claude", false)
        #expect(text(mac).contains("bypass_permissions = false") && !text(mac).contains("bypass_permissions = true"), "asking again asks nothing")
        #expect(mac.model.pendingLoosening == nil)
        await mac.model.setAgentBypass("claude", nil)
        #expect(!text(mac).contains("bypass_permissions"), "following the switch is the setting taken out")
    }

    private static let switchedOn = "[general]\nagents = [\"claude\", \"goose\"]\nbypass_permissions = true\n\n[agent.claude]\nbypass_permissions = false\n"

    @Test func everyControlThatWouldMakeAnAgentStartWithoutAskingIsHeldForTheYes() async throws {
        let mac = try await started(Self.switchedOn); defer { mac.cleanUp() }
        // "Same as all agents": the switch is on, so Claude Code would start without asking.
        await mac.model.setAgentBypass("claude", nil)
        #expect(text(mac) == Self.switchedOn && mac.model.pendingLoosening?.agents.map(\.agent) == ["claude"])
        mac.model.cancelLoosening()
        #expect(mac.model.pendingLoosening == nil && text(mac) == Self.switchedOn, "no is no: nothing was written")
        // A flag for the agent that has none (Goose): the question said it keeps asking.
        await mac.model.setAgentBypassArgument("goose", "--yolo")
        #expect(text(mac) == Self.switchedOn && mac.model.pendingLoosening?.agents == [PromptEffects.Entry(agent: "goose", name: "Goose", flag: "--yolo")])
        await mac.model.confirmLoosening()
        #expect(text(mac).contains("bypass_permission_arg = \"--yolo\""))
        // Putting an agent in the menu: it starts with a flag of its own (Codex's also turns its sandbox off).
        await mac.model.setAgent("codex", enabled: true)
        #expect(mac.model.pendingLoosening?.agents.map(\.agent) == ["codex"] && !text(mac).contains("\"codex\""))
        await mac.model.confirmLoosening()
        #expect(mac.model.general?.enabledAgents.map(\.id) == ["claude", "goose", "codex"])
    }

    /// The switch asked a question of its own, built from the window's last read of `general.agents`, and its yes was taken without the service's check: it named fewer agents than the yes
    /// starts without asking.
    @Test func theSwitchIsHeldLikeEveryOtherControlAndNamesEveryAgentItsYesStartsWithoutAsking() async throws {
        let config = "[general]\nagents = [\"claude\"]\n\n[services]\nitems = [\"open.terminal\", \"agent.codex\"]\n"
        let mac = try await started(config); defer { mac.cleanUp() }
        await mac.model.setBypassPermissions(true)
        #expect(text(mac) == config, "nothing is written before the yes")
        #expect(mac.model.pendingLoosening?.agents.map(\.agent) == ["claude", "codex"], "\(String(describing: mac.model.pendingLoosening?.agents))")
        mac.model.cancelLoosening()
        #expect(text(mac) == config && mac.model.general?.bypassPermissions == false)
        await mac.model.setBypassPermissions(true)
        await mac.model.confirmLoosening()
        #expect(text(mac).contains("bypass_permissions = true") && mac.model.general?.bypassPermissions == true)
        await mac.model.setBypassPermissions(false)
        #expect(mac.model.pendingLoosening == nil && mac.model.general?.bypassPermissions == false, "switching them back on needs no question")
    }

    @Test func theQuestionOfTheSwitchNamesTheAgentsOfTheFilesAsTheyAreNowNotAsTheWindowLastReadThem() async throws {
        let mac = try await started("[general]\nagents = [\"claude\"]\n"); defer { mac.cleanUp() }
        // An assistant puts Codex in the menu while the switch is off (nothing loosens then, so it is made at once); the window has not read the file again.
        let service = ConfigService(paths: mac.paths)
        _ = try service.submit([.insert("codex", into: "general.agents")], target: .shared, actor: .mcp)
        await mac.model.setBypassPermissions(true)
        #expect(mac.model.pendingLoosening?.agents.map(\.agent) == ["claude", "codex"], "\(String(describing: mac.model.pendingLoosening?.agents)): \(text(mac))")
    }

    @Test func nothingIsHeldWhileTheSwitchIsOff() async throws {
        let mac = try await started(Self.switchedOn.replacingOccurrences(of: "bypass_permissions = true", with: "bypass_permissions = false")); defer { mac.cleanUp() }
        await mac.model.setAgentBypass("claude", nil)
        await mac.model.setAgentBypassArgument("goose", "--yolo")
        await mac.model.setAgent("codex", enabled: true)
        #expect(mac.model.pendingLoosening == nil && text(mac).contains("--yolo") && mac.model.general?.enabledAgents.map(\.id) == ["claude", "goose", "codex"])
    }

    @Test func theArgumentsAreAddedChangedMovedAndTakenOutThroughTheModel() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        for argument in ["--a", "--b", "--c"] { await mac.model.addAgentArgument("claude", argument) }
        #expect(mac.model.agentOptions("claude")?.args == ["--a", "--b", "--c"], "\(text(mac))")
        await mac.model.setAgentArgument("claude", at: 2, from: "--b", to: "--bee")
        await mac.model.moveArgument(.agent("claude"), 3, by: -1)
        #expect(mac.model.agentOptions("claude")?.args == ["--a", "--c", "--bee"])
        await mac.model.moveArgument(.agent("claude"), 1, by: 1)
        #expect(mac.model.agentOptions("claude")?.args == ["--c", "--a", "--bee"])
        await mac.model.moveAgentArguments("claude", from: IndexSet(integer: 2), to: 0)
        #expect(mac.model.agentOptions("claude")?.args == ["--bee", "--c", "--a"])
        await mac.model.removeAgentArgument("claude", at: 1)
        #expect(mac.model.agentOptions("claude")?.args == ["--c", "--a"])
        #expect(try ConfigDocument(text(mac)).elements(of: "agent.claude.args") == ["--c", "--a"])
        await mac.model.moveArgument(.agent("claude"), 1, by: -1)
        await mac.model.moveArgument(.agent("claude"), 2, by: 1)
        #expect(mac.model.agentOptions("claude")?.args == ["--c", "--a"], "a move past an end does nothing")
    }

    @Test func anArgumentIsRemovedByPlaceOnlyFromTheListThatWasShown() async throws {
        let mac = try await started(Self.sample + "\n[agent.claude]\nargs = [\"--a\", \"--b\"]\n"); defer { mac.cleanUp() }
        _ = try service(mac).apply(.insert("--z", into: "agent.claude.args", at: 1), actor: .cli)
        let before = text(mac)
        await mac.model.removeAgentArgument("claude", at: 2)   // what the window shows as --b
        #expect(text(mac) == before, "another argument was not removed in its place")
        #expect(mac.model.notice == .listChanged && mac.model.configEdit == nil)
        #expect(mac.model.agentOptions("claude")?.args == ["--z", "--a", "--b"], "the window now shows the list as it is")
    }

    @Test func anAgentOfOnesOwnIsMadeWithItsFieldsPutInTheMenuAndItsPageClosesWhenItIsTakenBack() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(await mac.model.createAgent(name: "  ", command: "lazygit") == false)
        #expect(await mac.model.createAgent(name: "Lazy Git", command: "") == false)
        #expect(text(mac) == Self.sample, "nothing is made of an empty name or an empty command")
        #expect(await mac.model.createAgent(name: "Lazy Git", command: "lazygit"))
        #expect(text(mac).contains("[agent.lazy-git]\nname = \"Lazy Git\"\ncommand = \"lazygit\"\n"), "\(text(mac))")
        #expect(mac.model.general?.enabledAgents.map(\.id) == ["claude", "lazy-git"])
        #expect(mac.model.agentOptions("lazy-git")?.isBuiltIn == false)
        mac.model.openAgentOptions("lazy-git")
        #expect(mac.model.agentDetail == "lazy-git")
        await mac.model.undoEdit()
        #expect(text(mac) == Self.sample)
        #expect(mac.model.agentOptions("lazy-git") == nil && mac.model.agentDetail == nil, "the page of an agent that is gone is closed")
    }

    @Test func anAgentOfOnesOwnIsTakenOutAgainAndItsPageClosesWithIt() async throws {
        let mac = try await started(Self.sample + "\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n"); defer { mac.cleanUp() }
        _ = try service(mac).apply(.insert("mine", into: "general.agents", at: nil), actor: .cli)
        await mac.model.refresh()
        mac.model.openAgentOptions("mine")
        await mac.model.removeAgent("claude")
        #expect(text(mac).contains("[agent.mine]") && mac.model.agentOptions("claude") != nil, "a built-in agent is not in the config and is not taken out")
        await mac.model.removeAgent("mine")
        #expect(!text(mac).contains("mine"), "\(text(mac))")
        #expect(mac.model.general?.enabledAgents.map(\.id) == ["claude"] && mac.model.agentDetail == nil)
        #expect(mac.model.configEdit?.key == "agent.mine.command")
        await mac.model.undoEdit()
        #expect(text(mac).contains("[agent.mine]\nname = \"Mine\"") && mac.model.general?.enabledAgents.map(\.id) == ["claude", "mine"], "one Undo puts back the entry and the table")
    }

    @Test func theOptionsPageOfAnAgentThatSomethingElseTookOutIsClosedByTheNextRead() async throws {
        let mac = try await started(Self.sample + "\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n"); defer { mac.cleanUp() }
        mac.model.openAgentOptions("mine")
        #expect(mac.model.agentDetail == "mine")
        _ = try service(mac).apply([.removeTable("agent.mine")], actor: .cli)
        await mac.model.refresh()
        #expect(mac.model.agentOptions("mine") == nil && mac.model.agentDetail == nil)
    }

    @Test func anAgentIsNotMadeNextToAListThatChangedMeanwhile() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        _ = try service(mac).apply(.insert("codex", into: "general.agents", at: nil), actor: .cli)
        let before = text(mac)
        #expect(await mac.model.createAgent(name: "Lazy Git", command: "lazygit") == false)
        #expect(text(mac) == before && mac.model.notice == .listChanged, "nothing was made, and the window says why")
    }

    @Test func leavingTheAgentsSectionClosesTheOptionsPage() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        mac.model.select(.agents)
        mac.model.openAgentOptions("claude")
        mac.model.select(.agents)
        #expect(mac.model.agentDetail == "claude", "choosing the section that is open changes nothing")
        mac.model.select(.overview)
        #expect(mac.model.agentDetail == nil)
    }

    @Test func aConfigThatCannotBeEditedHasNoOptionsToEdit() async throws {
        let mac = try await started("[general]\nagents = [\"claude\"\nterminal = 5\n"); defer { mac.cleanUp() }
        #expect(mac.model.agentOptions("claude") == nil)
        let before = text(mac)
        await mac.model.setAgentCommand("claude", "claude --model opus")
        #expect(text(mac) == before)
    }

    // MARK: A change by place acts on what was shown, and a field on what it showed

    @Test func aSecondClickOnTheSameMinusTakesOutOneArgument() async throws {
        let mac = try await started(Self.sample + "\n[agent.claude]\nargs = [\"--a\", \"--b\", \"--c\"]\n"); defer { mac.cleanUp() }
        async let first = mac.model.removeAgentArgument("claude", at: 1)
        async let second = mac.model.removeAgentArgument("claude", at: 1)
        _ = await (first, second)
        #expect(mac.model.agentOptions("claude")?.args == ["--b", "--c"], "the second click was meant for the argument that was at that place when it was made")
        async let down = mac.model.moveArgument(.agent("claude"), 1, by: 1)
        async let again = mac.model.moveArgument(.agent("claude"), 1, by: 1)
        _ = await (down, again)
        #expect(mac.model.agentOptions("claude")?.args == ["--c", "--b"], "one move, not two")
    }

    @Test func aFieldThatShowedAnotherArgumentChangesNothing() async throws {
        let mac = try await started(Self.sample + "\n[agent.claude]\nargs = [\"--a\", \"--b\", \"--c\"]\n"); defer { mac.cleanUp() }
        // The field of argument 2 showed `--b`; an argument above it was taken out meanwhile, so `--c` is at that place now.
        await mac.model.removeAgentArgument("claude", at: 1)
        #expect(mac.model.agentOptions("claude")?.args == ["--b", "--c"])
        let before = text(mac)
        #expect(await mac.model.setAgentArgument("claude", at: 2, from: "--b", to: "--bee"))
        #expect(text(mac) == before && mac.model.agentOptions("claude")?.args == ["--b", "--c"], "`--c` was not typed over")
        await mac.model.setAgentArgument("claude", at: 1, from: "--b", to: "--bee")
        #expect(mac.model.agentOptions("claude")?.args == ["--bee", "--c"])
    }

    @Test func aRefusedChangeIsNotDoneAndAChangeThatWasNothingIs() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(await mac.model.setAgentCommand("claude", "claude") == true, "nothing to change is done")
        #expect(await mac.model.setAgentArgument("claude", at: 1, from: "x", to: "y") == true)
        #expect(await mac.model.addAgentArgument("claude", "bad\nline") == false, "a line break is refused, and what was typed is kept for the person to put right")
        #expect(mac.model.editRefusal != nil && !text(mac).contains("bad"))
    }

    // MARK: This Mac's own file

    private func startedOnAMac(shared: String, local: String) async throws -> Mac {
        let mac = try Mac()
        try mac.writeConfig(shared)
        try local.write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8)
        await mac.model.refresh()
        return mac
    }
    private func localText(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.localConfigFile, encoding: .utf8)) ?? "" }

    @Test func anAgentMadeWhileThisMacsFileListsTheAgentsCanBeGivenItsOtherOptions() async throws {
        let mac = try await startedOnAMac(shared: "[general]\nterminal = \"ghostty\"\n", local: "[general]\nagents = [\"claude\"]\n"); defer { mac.cleanUp() }
        #expect(await mac.model.createAgent(name: "Lazy Git", command: "lazygit"))
        #expect(localText(mac).contains("[agent.lazy-git]\nname = \"Lazy Git\"\ncommand = \"lazygit\""), "the table is made where the list is: \(localText(mac))")
        #expect(await mac.model.addAgentArgument("lazy-git", "--paging"))
        #expect(await mac.model.setAgentTerminal("lazy-git", "terminal"))
        #expect(await mac.model.setAgentBypass("lazy-git", false))
        #expect(localText(mac).contains("args = [\"--paging\"]") && localText(mac).contains("terminal = \"terminal\"") && !text(mac).contains("lazy-git"), "every key went to the file that holds the table")
        #expect(mac.model.agentOptions("lazy-git")?.args == ["--paging"])
    }

    @Test func undoGoesToTheFileTheChangeWasMadeInWhenItTookTheSettingOutOfThatFile() async throws {
        let mac = try await startedOnAMac(shared: Self.sample, local: "[agent.claude]\nterminal = \"terminal\"\n"); defer { mac.cleanUp() }
        #expect(mac.model.agentOptions("claude")?.terminal == "terminal")
        await mac.model.setAgentTerminal("claude", nil)
        #expect(mac.model.agentOptions("claude")?.terminal == nil && !localText(mac).contains("terminal"))
        await mac.model.undoEdit()
        #expect(localText(mac).contains("terminal = \"terminal\"") && mac.model.agentOptions("claude")?.terminal == "terminal", "\(localText(mac))")
    }

    @Test func anAgentWhoseTableIsInTheOtherFileThanTheListIsTakenOutOfBoth() async throws {
        let mac = try await startedOnAMac(shared: "[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n", local: "[general]\nagents = [\"claude\", \"mine\"]\n"); defer { mac.cleanUp() }
        #expect(mac.model.agentOptions("mine") != nil)
        await mac.model.removeAgent("mine")
        #expect(mac.model.agentOptions("mine") == nil && !text(mac).contains("mine") && !localText(mac).contains("mine"), "\(text(mac)) | \(localText(mac))")
        #expect(ConfigStore.load(paths: mac.paths).result.hasErrors == false, "every step left a config that reads")
    }

    @Test func anAgentThatThisMacsFileStillNamesIsNotTakenOutLeavingAnError() async throws {
        let shared = Self.sample + "\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n"
        let mac = try await startedOnAMac(shared: shared, local: "[agent.mine]\nterminal = \"terminal\"\n"); defer { mac.cleanUp() }
        _ = try service(mac).apply(.insert("mine", into: "general.agents", at: nil), actor: .cli)
        await mac.model.refresh()
        let before = text(mac)
        await mac.model.removeAgent("mine")
        #expect(text(mac) == before && mac.model.editRefusal != nil, "refused: the file of this Mac would have named an agent that is gone")
        #expect(ConfigStore.load(paths: mac.paths).result.hasErrors == false && mac.model.agentOptions("mine") != nil, "the config reads, and the page is still there")
    }

    @Test func aNewAgentTakesNoIdThatThisMacTurnsOffOrAnotherFileMakes() async throws {
        let mac = try await startedOnAMac(shared: Self.sample + "\n[agent.foo]\nname = \"Foo\"\ncommand = \"foo\"\n", local: "disabled = [\"foo\", \"bar\"]\n"); defer { mac.cleanUp() }
        #expect(mac.model.agentOptions("foo") == nil, "this Mac does not show it")
        // (A name that another agent has is refused, since the other Macs would then have two of one name: "Foo!" makes the id `foo` as well.)
        #expect(await mac.model.createAgent(name: "Foo", command: "foo") == false && mac.model.editRefusal != nil, "the shared file has an agent of that name for the other Macs")
        #expect(await mac.model.createAgent(name: "Foo!", command: "foo"))
        #expect(text(mac).contains("[agent.foo-2]") && mac.model.agentOptions("foo-2") != nil)
        #expect(await mac.model.createAgent(name: "Bar", command: "bar"))
        #expect(text(mac).contains("[agent.bar-2]") && mac.model.agentOptions("bar-2") != nil, "an id that is only disabled is taken too, or the agent would be written and never shown")
    }

    @Test func aNameThatReadsAsSomethingElseIsRefusedAndNothingIsWritten() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(await mac.model.createAgent(name: "Claude Code\u{202E}x", command: "evil") == false)
        #expect(text(mac) == Self.sample && mac.model.editRefusal != nil)
        #expect(await mac.model.createAgent(name: "Lazy\u{200B}Git", command: "lazygit") == false)
        #expect(text(mac) == Self.sample)
    }
}

@Suite("The setup window's model: the prompt presets")
@MainActor
struct SetupModelPresetTests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"

    private func text(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.configFile, encoding: .utf8)) ?? "" }
    private func localText(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.localConfigFile, encoding: .utf8)) ?? "" }
    private func service(_ mac: Mac) -> ConfigService { ConfigService(paths: mac.paths, environment: [:]) }

    private func started(_ config: String = SetupModelPresetTests.sample, local: String? = nil) async throws -> Mac {
        let mac = try Mac()
        try mac.writeConfig(config)
        if let local { try local.write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8) }
        await mac.model.refresh()
        return mac
    }

    @Test func aPresetOfOnesOwnIsMadeEditedAndTakenOut() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(mac.model.presets?.rows.map(\.id) == ["review", "explain", "tests"] && mac.model.presets?.rows.allSatisfy { $0.origin == .builtIn } == true)
        #expect(await mac.model.createPreset(title: "Find Bugs", prompt: "Find bugs in {files}."))
        #expect(text(mac).contains("[[preset]]\nid = \"find-bugs\"\ntitle = \"Find Bugs\"\nprompt = \"Find bugs in {files}.\"\n"), "\(text(mac))")
        #expect(mac.model.preset("find-bugs")?.origin == .own && mac.model.presets?.rows.last?.id == "find-bugs")
        #expect(await mac.model.setPresetTitle("find-bugs", "Bug hunt"))
        #expect(await mac.model.setPresetPrompt("find-bugs", "Hunt for bugs in {files}."))
        #expect(await mac.model.setPresetAgent("find-bugs", "claude"))
        #expect(await mac.model.setPresetMaxFiles("find-bugs", 7))
        let row = try #require(mac.model.preset("find-bugs"))
        #expect(row.title == "Bug hunt" && row.prompt == "Hunt for bugs in {files}." && row.agent == "claude" && row.maxFiles == 7, "\(text(mac))")
        await mac.model.undoEdit()
        #expect(mac.model.preset("find-bugs")?.maxFiles == AgentPreset.defaultMaxFiles, "one Undo takes back the last change")
        mac.model.openPreset("find-bugs")
        await mac.model.removePreset("find-bugs")
        #expect(mac.model.preset("find-bugs") == nil && mac.model.presetDetail == nil && !text(mac).contains("find-bugs"), "its page closes with it")
    }

    @Test func aNewPresetTakesNoIdThatAFileHasEvenWhenTheWindowDoesNotShowItYet() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        // Another tool added a preset after the window read the config.
        try (Self.sample + "\n[[preset]]\nid = \"find-bugs\"\ntitle = \"Theirs\"\nprompt = \"Look at {files}.\"\n").write(to: mac.paths.configFile, atomically: true, encoding: .utf8)
        #expect(mac.model.preset("find-bugs") == nil)
        #expect(await mac.model.createPreset(title: "Find Bugs", prompt: "Find bugs in {files}."))
        #expect(text(mac).contains("id = \"find-bugs-2\"") && text(mac).contains("title = \"Theirs\""), "\(text(mac))")
    }

    @Test func aBuiltInPresetIsMadeTheOwnersChangedAndPutBack() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(await mac.model.setPresetTitle("review", "Strict"), "a built-in preset has no entry to change: nothing is done")
        #expect(text(mac) == Self.sample)
        await mac.model.customizePreset("review")
        #expect(mac.model.preset("review")?.origin == .customized && text(mac).contains("id = \"review\""))
        #expect(await mac.model.setPresetPrompt("review", "Be strict about {files}."))
        #expect(mac.model.preset("review")?.prompt == "Be strict about {files}." && mac.model.presets?.rows.map(\.id) == ["review", "explain", "tests"], "replaced in place")
        await mac.model.removePreset("review")
        #expect(mac.model.preset("review")?.origin == .builtIn && text(mac) == Self.sample, "the built-in preset is back, and the file is as it was")
    }

    @Test func aPresetThatThisMacsFileWritesIsChangedInThatFile() async throws {
        let shared = Self.sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n"
        let mac = try await started(shared, local: "[[preset]]\nid = \"other\"\ntitle = \"Other\"\nprompt = \"Read {files}.\"\n"); defer { mac.cleanUp() }
        #expect(mac.model.preset("mine")?.entry == PresetRowState.Entry(target: .shared, position: 1) && mac.model.preset("other")?.entry == PresetRowState.Entry(target: .local, position: 1), "position 1 of each file is another preset")
        #expect(await mac.model.setPresetTitle("other", "Other one"))
        #expect(localText(mac).contains("title = \"Other one\"") && text(mac) == shared)
        #expect(await mac.model.setPresetTitle("mine", "Mine now"))
        #expect(text(mac).contains("title = \"Mine now\"") && localText(mac).contains("title = \"Other one\""))
        await mac.model.undoEdit()
        #expect(text(mac) == shared && localText(mac).contains("Other one"), "Undo goes to the file the change was made in")
    }

    @Test func aPresetThatMovedUnderTheEditIsNotChangedInPlaceOfAnother() async throws {
        let shared = Self.sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n"
        let mac = try await started(shared); defer { mac.cleanUp() }
        // Something else puts a preset above it: place 1 is not `mine` any more.
        _ = try service(mac).apply(.addEntry(to: "preset", fields: [ConfigField("id", .string("first")), ConfigField("title", .string("First")), ConfigField("prompt", .string("Do {files}."))], at: 1), actor: .cli)
        let before = text(mac)
        #expect(await mac.model.setPresetTitle("mine", "Changed") == false)
        #expect(text(mac) == before && mac.model.notice == .listChanged, "refused, and the window says the list changed")
        #expect(mac.model.preset("mine")?.entry?.position == 2, "and it reads again")
    }

    @Test func aPresetsPageIsClosedWhenSomethingElseTakesItOutAndTheWindowReadsAgain() async throws {
        let mac = try await started(Self.sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n"); defer { mac.cleanUp() }
        mac.model.select(.agents)
        mac.model.openPreset("mine")
        _ = try service(mac).apply(.removeEntry(at: 1, from: "preset"), actor: .cli)
        await mac.model.refresh()
        #expect(mac.model.preset("mine") == nil && mac.model.presetDetail == nil)
    }

    @Test func aPromptTheConfigRefusesIsNotWrittenAndWhatWasTypedIsKept() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        await mac.model.customizePreset("explain")
        let before = text(mac)
        #expect(await mac.model.setPresetPrompt("explain", "line\nbreak {files}") == false)
        #expect(await mac.model.setPresetPrompt("explain", "unknown {file} placeholder") == false)
        #expect(await mac.model.setPresetPrompt("explain", "-starts with a dash {files}") == false)
        #expect(text(mac) == before && mac.model.editRefusal != nil)
        #expect(await mac.model.createPreset(title: "A", prompt: "bad\\slash {files}") == false && text(mac) == before)
    }

    @Test func leavingTheAgentsSectionClosesAPresetsPage() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        mac.model.select(.agents)
        mac.model.openPreset("review")
        #expect(mac.model.presetDetail == "review" && mac.model.agentDetail == nil)
        mac.model.openAgentOptions("claude")
        #expect(mac.model.presetDetail == nil && mac.model.agentDetail == "claude", "one page at a time")
        mac.model.openPreset("tests")
        mac.model.select(.overview)
        #expect(mac.model.presetDetail == nil)
    }
}

@Suite("The setup window's model: the new-file templates")
@MainActor
struct SetupModelNewFileTests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"

    private func text(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.configFile, encoding: .utf8)) ?? "" }
    private func localText(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.localConfigFile, encoding: .utf8)) ?? "" }

    private func started(_ config: String = SetupModelNewFileTests.sample, local: String? = nil) async throws -> Mac {
        let mac = try Mac()
        try mac.writeConfig(config)
        if let local { try local.write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8) }
        await mac.model.refresh()
        return mac
    }

    @Test func theBuiltInTemplatesAreWrittenOutAsTheConfigsOwnByTheFirstChange() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(mac.model.newFile?.isBuiltIn == true && mac.model.newFile?.rows.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx"])
        #expect(await mac.model.setTemplateTitle("txt", "Notes"), "a built-in template has no entry to change: nothing is done")
        #expect(text(mac) == Self.sample)
        await mac.model.customizeTemplates()
        #expect(mac.model.newFile?.isBuiltIn == false && mac.model.newFile?.rows.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx"] && text(mac).contains("[[new_file.template]]\nid = \"txt\""), "\(text(mac))")
        #expect(await mac.model.setTemplateTitle("txt", "Notes"))
        #expect(mac.model.template("txt")?.title == "Notes")
        await mac.model.undoEdit()
        #expect(mac.model.template("txt")?.title == "Text Document")
    }

    @Test func aTemplateIsMadeEditedAndTakenOutAndTheLastOneGivesTheBuiltInOnesBack() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(await mac.model.createTemplate(title: "Python Script", fileExtension: ".py"))
        #expect(mac.model.newFile?.rows.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx", "python-script"] && mac.model.template("python-script")?.fileExtension == "py", "the built-in templates were written out first: \(text(mac))")
        #expect(await mac.model.setTemplateContents("python-script", "#!/usr/bin/env python3\nprint(1)\n"))
        #expect(await mac.model.setTemplateBaseName("python-script", "main"))
        #expect(await mac.model.setTemplateExtension("python-script", "pyw"))
        let row = try #require(mac.model.template("python-script"))
        #expect(row.contents == "#!/usr/bin/env python3\nprint(1)\n" && row.baseName == "main" && row.fileExtension == "pyw", "\(text(mac))")
        #expect(await mac.model.setTemplateOpensWith("python-script", "vscode"))
        #expect(mac.model.template("python-script")?.openWith == "vscode")
        mac.model.openTemplate("python-script")
        await mac.model.removeTemplate("python-script")
        #expect(mac.model.template("python-script") == nil && mac.model.templateDetail == nil)
        for id in ["txt", "md", "docx", "xlsx", "pptx"] { await mac.model.removeTemplate(id) }
        #expect(mac.model.newFile?.isBuiltIn == true && text(mac) == Self.sample, "taking the last one out gives the built-in templates back, and the file as it was")
    }

    @Test func aNewTemplateTakesNoIdThatAFileHasEvenWhenTheWindowDoesNotShowItYet() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        await mac.model.customizeTemplates()
        // Another tool added a template after the window read the config.
        try (text(mac) + "\n[[new_file.template]]\nid = \"python-script\"\ntitle = \"Theirs\"\nextension = \"py\"\n").write(to: mac.paths.configFile, atomically: true, encoding: .utf8)
        #expect(mac.model.template("python-script") == nil)
        #expect(await mac.model.createTemplate(title: "Python Script", fileExtension: "py"))
        #expect(text(mac).contains("id = \"python-script-2\"") && text(mac).contains("title = \"Theirs\""), "\(text(mac))")
    }

    @Test func whatHappensAfterAFileIsMadeIsChosenAndTheDefaultIsTheSettingTakenOut() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        await mac.model.setNewFileThen(.open)
        #expect(text(mac).contains("[new_file]\nthen = \"open\"") && mac.model.newFile?.then == .open)
        await mac.model.setNewFileThen(.reveal)
        #expect(!text(mac).contains("then") && mac.model.newFile?.then == .reveal)
    }

    @Test func aTemplateInThisMacsFileIsChangedInThatFile() async throws {
        let shared = Self.sample + "\n[[new_file.template]]\nid = \"a\"\ntitle = \"A\"\nextension = \"a\"\n"
        let mac = try await started(shared, local: "[[new_file.template]]\nid = \"b\"\ntitle = \"B\"\nextension = \"b\"\n"); defer { mac.cleanUp() }
        #expect(mac.model.template("a")?.entry == EntryLocation(target: .shared, position: 1) && mac.model.template("b")?.entry == EntryLocation(target: .local, position: 1))
        #expect(await mac.model.setTemplateTitle("b", "Bee"))
        #expect(localText(mac).contains("title = \"Bee\"") && text(mac) == shared)
        await mac.model.undoEdit()
        #expect(localText(mac).contains("title = \"B\""))
    }

    @Test func aTemplateTheConfigRefusesIsNotWrittenAndWhatWasTypedIsKept() async throws {
        let mac = try await started(Self.sample + "\n[[new_file.template]]\nid = \"a\"\ntitle = \"A\"\nextension = \"a\"\n"); defer { mac.cleanUp() }
        let before = text(mac)
        #expect(await mac.model.setTemplateExtension("a", "x/y") == false)
        #expect(await mac.model.setTemplateBaseName("a", "a/b") == false)
        #expect(await mac.model.setTemplateOpensWith("a", "no-such-app") == false)
        #expect(text(mac) == before && mac.model.editRefusal != nil)
        #expect(await mac.model.createTemplate(title: "Bad", fileExtension: "a.b") == false && text(mac) == before)
    }

    @Test func whatHappensAfterAFileIsMadeIsWrittenToTheFileThatDecidesItOnThisMac() async throws {
        let mac = try await started(local: "[new_file]\nthen = \"nothing\"\n"); defer { mac.cleanUp() }
        #expect(mac.model.newFile?.then == .nothing)
        await mac.model.setNewFileThen(.open)
        #expect(localText(mac).contains("then = \"open\"") && text(mac) == Self.sample && mac.model.newFile?.then == .open, "this Mac's own file decides, so the change goes there: \(localText(mac))")
    }

    @Test func aTemplateThisMacTurnsOffStaysInTheSharedFileWhenTheFirstNewTemplateIsMade() async throws {
        let mac = try await started(local: "disabled = [\"md\"]\n"); defer { mac.cleanUp() }
        #expect(mac.model.newFile?.rows.map(\.id) == ["txt", "docx", "xlsx", "pptx"] && mac.model.newFile?.isBuiltIn == true)
        #expect(await mac.model.createTemplate(title: "Python Script", fileExtension: "py"))
        #expect(mac.model.newFile?.rows.map(\.id) == ["txt", "docx", "xlsx", "pptx", "python-script"], "the one this Mac turns off stays off here")
        #expect(text(mac).contains("id = \"txt\"") && text(mac).contains("id = \"md\"") && text(mac).contains("id = \"python-script\""), "and every other Mac still has both built-in templates: \(text(mac))")
    }

    @Test func aNewTemplateTakesNoIdThatThisMacTurnsOff() async throws {
        let mac = try await started(Self.sample + "\n[[new_file.template]]\nid = \"notes\"\ntitle = \"Notes\"\nextension = \"txt\"\n", local: "disabled = [\"python\"]\n"); defer { mac.cleanUp() }
        #expect(await mac.model.createTemplate(title: "Python", fileExtension: "py"), "the first Add makes a template that is shown")
        #expect(mac.model.newFile?.rows.map(\.id) == ["notes", "python-2"] && !text(mac).contains("id = \"python\"\n"), "\(text(mac))")
    }

    @Test func aTemplatesPageIsClosedWhenSomethingElseTakesItOutAndTheWindowReadsAgain() async throws {
        let mac = try await started(Self.sample + "\n[[new_file.template]]\nid = \"a\"\ntitle = \"A\"\nextension = \"a\"\n"); defer { mac.cleanUp() }
        mac.model.select(.menu)
        mac.model.openTemplate("a")
        _ = try ConfigService(paths: mac.paths, environment: [:]).apply(.removeEntry(at: 1, from: "new_file.template"), actor: .cli)
        await mac.model.refresh()
        #expect(mac.model.template("a") == nil && mac.model.templateDetail == nil)
    }

    @Test func aTemplatePageIsLeftWhenTheSectionIsLeft() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        mac.model.select(.menu)
        mac.model.openTemplate("txt")
        #expect(mac.model.templateDetail == "txt")
        mac.model.select(.overview)
        #expect(mac.model.templateDetail == nil)
    }
}

@Suite("The setup window's model: an agent's start options")
@MainActor
struct SetupModelVariantTests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"

    private func text(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.configFile, encoding: .utf8)) ?? "" }
    private func localText(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.localConfigFile, encoding: .utf8)) ?? "" }
    private func service(_ mac: Mac) -> ConfigService { ConfigService(paths: mac.paths, environment: [:]) }

    private func started(_ config: String = SetupModelVariantTests.sample, local: String? = nil) async throws -> Mac {
        let mac = try Mac()
        try mac.writeConfig(config)
        if let local { try local.write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8) }
        await mac.model.refresh()
        return mac
    }

    private func arguments(_ mac: Mac, _ id: String = "use-opus") -> [String]? { mac.model.variant("claude", id)?.arguments.items }

    @Test func aStartOptionIsMadeEditedAndTakenOut() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(mac.model.agentOptions("claude")?.variants.isEmpty == true && mac.model.agentOptions("claude")?.fixedVariants.map(\.id) == ["continue", "resume"])
        #expect(await mac.model.createVariant(agent: "claude", title: "Use Opus") != nil)
        #expect(text(mac).contains("[[agent.claude.variant]]\nid = \"use-opus\"\ntitle = \"Use Opus\"\n"), "\(text(mac))")
        let owner = ArgumentListOwner.variant(agent: "claude", id: "use-opus")
        let first = await mac.model.addArgument(owner, "--model"), second = await mac.model.addArgument(owner, "opus"), third = await mac.model.addArgument(owner, "--verbose")
        #expect(first && second && third)
        #expect(arguments(mac) == ["--model", "opus", "--verbose"] && text(mac).contains("arguments = [\"--model\", \"opus\", \"--verbose\"]"), "\(text(mac))")
        #expect(await mac.model.setArgument(owner, at: 2, from: "opus", to: "sonnet"))
        #expect(await mac.model.moveArgument(owner, 3, by: -1))
        #expect(arguments(mac) == ["--model", "--verbose", "sonnet"])
        #expect(await mac.model.removeArgument(owner, at: 2))
        #expect(arguments(mac) == ["--model", "sonnet"])
        #expect(await mac.model.setVariantTitle("claude", "use-opus", "Use Sonnet"))
        #expect(mac.model.variant("claude", "use-opus")?.title == "Use Sonnet")
        await mac.model.undoEdit()
        #expect(mac.model.variant("claude", "use-opus")?.title == "Use Opus", "one Undo takes back the last change")
        mac.model.openVariant(VariantRef(agent: "claude", id: "use-opus"))
        await mac.model.removeVariant("claude", "use-opus")
        #expect(mac.model.variant("claude", "use-opus") == nil && mac.model.variantDetail == nil && !text(mac).contains("use-opus"), "its page closes with it")
    }

    @Test func aStartOptionInThisMacsFileIsChangedInThatFile() async throws {
        let shared = Self.sample + "\n[[agent.claude.variant]]\nid = \"a\"\ntitle = \"A\"\narguments = [\"--a\"]\n"
        let mac = try await started(shared, local: "[[agent.claude.variant]]\nid = \"b\"\ntitle = \"B\"\narguments = [\"--b\"]\n"); defer { mac.cleanUp() }
        #expect(mac.model.variant("claude", "a")?.entry == EntryLocation(target: .shared, position: 1) && mac.model.variant("claude", "b")?.entry == EntryLocation(target: .local, position: 1), "place 1 of each file is another start option")
        #expect(await mac.model.addArgument(.variant(agent: "claude", id: "b"), "--more"))
        #expect(localText(mac).contains("arguments = [\"--b\", \"--more\"]") && text(mac) == shared)
        #expect(await mac.model.setVariantTitle("claude", "a", "Aye"))
        #expect(text(mac).contains("title = \"Aye\"") && localText(mac).contains("title = \"B\""))
        await mac.model.undoEdit()
        #expect(text(mac) == shared && localText(mac).contains("--more"), "Undo goes to the file the change was made in")
    }

    @Test func aStartOptionThatMovedUnderTheEditIsNotChangedInPlaceOfAnother() async throws {
        let shared = Self.sample + "\n[[agent.claude.variant]]\nid = \"mine\"\ntitle = \"Mine\"\narguments = [\"--x\"]\n"
        let mac = try await started(shared); defer { mac.cleanUp() }
        _ = try service(mac).apply(.addEntry(to: "agent.claude.variant", fields: [ConfigField("id", .string("first")), ConfigField("title", .string("First"))], at: 1), actor: .cli)
        var before = text(mac)
        #expect(await mac.model.setVariantTitle("claude", "mine", "Changed") == false)
        #expect(text(mac) == before && mac.model.notice == .listChanged, "refused, and the window says the list changed")
        #expect(mac.model.variant("claude", "mine")?.entry.position == 2, "and it reads again")
        // The same for a change of its arguments, which is worked out from the place too.
        _ = try service(mac).apply(.addEntry(to: "agent.claude.variant", fields: [ConfigField("id", .string("second")), ConfigField("title", .string("Second"))], at: 1), actor: .cli)
        before = text(mac)
        #expect(await mac.model.addArgument(.variant(agent: "claude", id: "mine"), "--y") == false)
        #expect(text(mac) == before && mac.model.variant("claude", "mine")?.entry.position == 3)
    }

    @Test func aNewStartOptionTakesNoIdThatAFileHasEvenWhenTheWindowDoesNotShowItYet() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        try (Self.sample + "\n[[agent.claude.variant]]\nid = \"use-opus\"\ntitle = \"Theirs\"\n").write(to: mac.paths.configFile, atomically: true, encoding: .utf8)
        #expect(mac.model.variant("claude", "use-opus") == nil)
        #expect(await mac.model.createVariant(agent: "claude", title: "Use Opus") != nil)
        #expect(text(mac).contains("id = \"use-opus-2\"") && text(mac).contains("title = \"Theirs\""), "\(text(mac))")
    }

    @Test func aStartOptionOfAnAgentOfOnesOwnIsWrittenInTheFileThatMadeTheAgent() async throws {
        let mine = "[general]\nagents = [\"claude\", \"mine\"]\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n"
        let mac = try await started(Self.sample, local: mine); defer { mac.cleanUp() }
        #expect(mac.model.agentOptions("mine") != nil)
        #expect(await mac.model.createVariant(agent: "mine", title: "Fast") != nil)
        #expect(localText(mac).contains("[[agent.mine.variant]]\nid = \"fast\"") && !text(mac).contains("agent.mine"), "the entry goes where the agent is defined, so that the shared file alone still reads")
    }

    @Test func aTitleOrAnArgumentTheConfigRefusesIsNotWrittenAndWhatWasTypedIsKept() async throws {
        let mac = try await started(Self.sample + "\n[[agent.claude.variant]]\nid = \"a\"\ntitle = \"A\"\narguments = [\"--a\"]\n"); defer { mac.cleanUp() }
        let before = text(mac)
        let owner = ArgumentListOwner.variant(agent: "claude", id: "a")
        #expect(await mac.model.setVariantTitle("claude", "a", "two\nlines") == false)
        #expect(await mac.model.addArgument(owner, "line\nbreak") == false)
        #expect(await mac.model.setArgument(owner, at: 1, from: "--a", to: "bad\\slash") == false)
        #expect(text(mac) == before && mac.model.editRefusal != nil)
        #expect(await mac.model.createVariant(agent: "claude", title: "bad\u{202E}title") == nil && text(mac) == before)
    }

    @Test func thePromptArgumentOfAnAgentIsSetThroughTheModel() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(await mac.model.setAgentPromptArgument("claude", "-i"))
        #expect(text(mac).contains("[agent.claude]\nprompt_arg = \"-i\"") && mac.model.agentOptions("claude")?.promptArgument == "-i", "\(text(mac))")
        #expect(await mac.model.setAgentPromptArgument("claude", "not a flag") == false && mac.model.editRefusal != nil, "the config says which words are not one")
        #expect(await mac.model.setAgentPromptArgument("claude", "positional"), "the built-in way is the setting taken out")
        #expect(mac.model.agentOptions("claude")?.promptArgument == nil && !text(mac).contains("prompt_arg"))
    }

    @Test func aStartOptionsPageIsClosedWhenSomethingElseTakesItOutAndTheWindowReadsAgain() async throws {
        let mac = try await started(Self.sample + "\n[[agent.claude.variant]]\nid = \"a\"\ntitle = \"A\"\n"); defer { mac.cleanUp() }
        mac.model.select(.agents)
        mac.model.openAgentOptions("claude")
        mac.model.openVariant(VariantRef(agent: "claude", id: "a"))
        #expect(mac.model.variantDetail == VariantRef(agent: "claude", id: "a"))
        _ = try service(mac).apply(.removeEntry(at: 1, from: "agent.claude.variant"), actor: .cli)
        await mac.model.refresh()
        #expect(mac.model.variant("claude", "a") == nil && mac.model.variantDetail == nil)
    }

    @Test func aStartOptionsPageIsLeftWhenItsAgentsPageOrTheSectionIsLeft() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        mac.model.select(.agents)
        mac.model.openAgentOptions("claude")
        mac.model.openVariant(VariantRef(agent: "claude", id: "continue"))
        #expect(mac.model.variantDetail == VariantRef(agent: "claude", id: "continue"))
        mac.model.openAgentOptions(nil)
        #expect(mac.model.variantDetail == nil)
        mac.model.openVariant(VariantRef(agent: "claude", id: "x"))
        mac.model.select(.overview)
        #expect(mac.model.variantDetail == nil)
    }
}

@Suite("The setup window's model: what review 23 found in the presets and templates")
@MainActor
struct SetupModelReviewTests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"
    private func text(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.configFile, encoding: .utf8)) ?? "" }
    private func localText(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.localConfigFile, encoding: .utf8)) ?? "" }
    private func service(_ mac: Mac) -> ConfigService { ConfigService(paths: mac.paths, environment: [:]) }

    private func started(_ config: String = SetupModelReviewTests.sample, local: String? = nil, patience: Duration? = nil) async throws -> Mac {
        let mac = try Mac(patience: patience)
        try mac.writeConfig(config)
        if let local { try local.write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8) }
        await mac.model.refresh()
        return mac
    }

    private static let twoPresets = sample + "\n[[preset]]\nid = \"one\"\ntitle = \"One\"\nprompt = \"Look at {files}.\"\n\n[[preset]]\nid = \"two\"\ntitle = \"Two\"\nprompt = \"Read {files}.\"\n"
    private static let twoTemplates = sample + "\n[[new_file.template]]\nid = \"a\"\ntitle = \"A\"\nextension = \"a\"\n\n[[new_file.template]]\nid = \"b\"\ntitle = \"B\"\nextension = \"b\"\n"

    // MARK: Pages that have nothing to show any more

    @Test func theBuiltInTemplatesComingBackCloseThePageOfTheTemplateThatWasTakenOut() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        mac.model.select(.menu)
        await mac.model.customizeTemplates()
        for id in ["md", "docx", "xlsx", "pptx"] { await mac.model.removeTemplate(id) }
        mac.model.openTemplate("txt")
        await mac.model.removeTemplate("txt")
        #expect(mac.model.newFile?.isBuiltIn == true && text(mac) == Self.sample, "the built-in templates are back, and the file is as it was")
        #expect(mac.model.templateDetail == nil, "a built-in template has no page: it has nothing to change")
    }

    @Test func undoingTheCustomizingClosesThePageOfATemplateThatIsBuiltInAgain() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        mac.model.select(.menu)
        await mac.model.customizeTemplates()
        mac.model.openTemplate("txt")
        await mac.model.undoEdit()
        #expect(mac.model.newFile?.isBuiltIn == true && mac.model.templateDetail == nil)
    }

    // MARK: Two clicks, two changes, two reads

    @Test func aSecondClickOnARemovingButtonDoesNothingAndSaysNothingOfAnotherList() async throws {
        let mac = try await started(Self.twoPresets); defer { mac.cleanUp() }
        mac.model.select(.agents)
        mac.model.openPreset("one")
        async let first: Void = mac.model.removePreset("one")
        async let second: Void = mac.model.removePreset("one")
        _ = await (first, second)
        #expect(mac.model.preset("one") == nil && mac.model.preset("two") != nil && mac.model.presetDetail == nil)
        #expect(mac.model.configEdit != nil && mac.model.editRefusal == nil, "the note of the removal, and not a refusal that contradicts it")
    }

    @Test func aSecondClickOnRemoveTemplateDoesNothingAndSaysNothingOfAnotherList() async throws {
        let mac = try await started(Self.twoTemplates); defer { mac.cleanUp() }
        mac.model.select(.menu)
        mac.model.openTemplate("a")
        async let first: Void = mac.model.removeTemplate("a")
        async let second: Void = mac.model.removeTemplate("a")
        _ = await (first, second)
        #expect(mac.model.template("a") == nil && mac.model.template("b") != nil)
        #expect(mac.model.configEdit != nil && mac.model.editRefusal == nil)
    }

    @Test func aSecondClickOnUseTheBuiltInPresetDoesNothingAndSaysNothingOfAnotherList() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        await mac.model.customizePreset("review")
        _ = await mac.model.createPreset(title: "Mine", prompt: "Look at {files}.")
        async let first: Void = mac.model.removePreset("review")
        async let second: Void = mac.model.removePreset("review")
        _ = await (first, second)
        #expect(mac.model.preset("review")?.origin == .builtIn && mac.model.editRefusal == nil)
    }

    @Test func twoChangesOfAPresetMadeAtOnceAreBothMade() async throws {
        let mac = try await started(Self.sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n"); defer { mac.cleanUp() }
        async let title = mac.model.setPresetTitle("mine", "Mine now")
        async let agent = mac.model.setPresetAgent("mine", "claude")
        _ = await (title, agent)
        #expect(text(mac).contains("title = \"Mine now\"") && text(mac).contains("agent = \"claude\""), "\(text(mac))")
    }

    @Test func twoChangesOfATemplateMadeAtOnceAreBothMade() async throws {
        let mac = try await started(Self.sample + "\n[[new_file.template]]\nid = \"a\"\ntitle = \"A\"\nextension = \"a\"\n"); defer { mac.cleanUp() }
        async let title = mac.model.setTemplateTitle("a", "Aa")
        async let app = mac.model.setTemplateOpensWith("a", "vscode")
        _ = await (title, app)
        #expect(text(mac).contains("title = \"Aa\"") && text(mac).contains("open_with = \"vscode\""), "\(text(mac))")
    }

    @Test func aReadThatBeganBeforeAnEditDoesNotPutTheOldPresetsAndTemplatesBack() async throws {
        let mac = try await started(Self.sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n\n[[new_file.template]]\nid = \"a\"\ntitle = \"A\"\nextension = \"a\"\n"); defer { mac.cleanUp() }
        var stale = try #require(mac.model.snapshot)
        stale.readAt = .now
        try await Task.sleep(for: .milliseconds(5))
        _ = await mac.model.setPresetTitle("mine", "Mine now")
        _ = await mac.model.setTemplateTitle("a", "Aa")
        mac.model.apply(stale)
        #expect(mac.model.preset("mine")?.title == "Mine now" && mac.model.template("a")?.title == "Aa")
    }

    @Test func aPageOfSomethingRhTookOutIsClosedByTheNextRead() async throws {
        let mac = try await started(Self.sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n\n[[new_file.template]]\nid = \"a\"\ntitle = \"A\"\nextension = \"a\"\n\n[[new_file.template]]\nid = \"b\"\ntitle = \"B\"\nextension = \"b\"\n"); defer { mac.cleanUp() }
        mac.model.openPreset("mine")
        mac.model.openTemplate("a")
        _ = try service(mac).apply([.removeEntry(at: 1, from: "preset"), .removeEntry(at: 1, from: "new_file.template")], actor: .cli)
        await mac.model.refresh()
        #expect(mac.model.presetDetail == nil && mac.model.templateDetail == nil)
    }

    // MARK: Where the note and the refusal of a change are said

    @Test func theNotesOfPresetsAndTemplatesAreSaidUnderTheirOwnEditor() async throws {
        let mac = try await started(Self.sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n\n[[new_file.template]]\nid = \"a\"\ntitle = \"A\"\nextension = \"a\"\n\n[[new_file.template]]\nid = \"b\"\ntitle = \"B\"\nextension = \"b\"\n"); defer { mac.cleanUp() }
        _ = await mac.model.setPresetTitle("mine", "Mine now")
        #expect(mac.model.configEdit?.tab == .agents && mac.model.configEdit?.key.hasPrefix("preset.") == true)
        _ = await mac.model.setTemplateTitle("a", "Aa")
        #expect(mac.model.configEdit?.tab == .menu && mac.model.configEdit?.key.hasPrefix("new_file.") == true)
        await mac.model.setNewFileThen(.open)
        #expect(mac.model.configEdit?.tab == .menu && mac.model.configEdit?.key.hasPrefix("new_file.") == true)
        await mac.model.removeTemplate("b")
        #expect(mac.model.configEdit?.tab == .menu && mac.model.configEdit?.key.hasPrefix("new_file.") == true)
        await mac.model.removePreset("mine")
        #expect(mac.model.configEdit?.tab == .agents && mac.model.configEdit?.key.hasPrefix("preset.") == true)
        #expect(await mac.model.setTemplateExtension("a", "x/y") == false)
        #expect(mac.model.editRefusal?.tab == .menu && mac.model.editRefusal?.key.hasPrefix("new_file.") == true, "the templates say it, and the banner of the menu rows does not")
    }

    @Test func theNoteOfATemplateSurvivesEditMenuAndTheNoteOfARowDoesNot() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        mac.model.select(.menu)
        await mac.model.setNewFileThen(.open)
        mac.model.setEditingMenu(true)
        #expect(mac.model.configEdit?.key == "new_file.then", "the templates panel's note, with its Undo, is not the menu editor's to end")
        await mac.model.moveMenuRow(1, by: 1)
        #expect(mac.model.configEdit?.key == MenuEditorState.key)
        mac.model.setEditingMenu(false)
        #expect(mac.model.configEdit == nil)
    }

    // MARK: The built-in templates and the other Macs

    @Test func aNewTemplateWhenOnlyThisMacsFileDefinesTemplatesStaysInThatFileAndChangesNothingForTheOtherMacs() async throws {
        let mac = try await started(local: "[[new_file.template]]\nid = \"mine\"\ntitle = \"Mine\"\nextension = \"mine\"\n"); defer { mac.cleanUp() }
        #expect(mac.model.newFile?.isBuiltIn == false && mac.model.newFile?.rows.map(\.id) == ["mine"])
        #expect(await mac.model.createTemplate(title: "Python Script", fileExtension: "py"))
        #expect(text(mac) == Self.sample, "the shared file is what the other Macs read: they keep Text Document and Markdown Document")
        #expect(mac.model.newFile?.rows.map(\.id) == ["mine", "python-script"] && localText(mac).contains("id = \"python-script\""), "\(localText(mac))")
        #expect(ConfigParser.parse(text(mac)).config.newFile.templates == NewFileTemplate.builtIn)
    }

    @Test func aMacThatTurnsOffAllTheTemplatesOfTheSharedFileGetsItsBuiltInOnesInItsOwnFileAndTheOtherMacsAreNotTouched() async throws {
        let shared = Self.sample + "\n[[new_file.template]]\nid = \"notes\"\ntitle = \"Notes\"\nextension = \"md\"\n\n[[new_file.template]]\nid = \"todo\"\ntitle = \"Todo\"\nextension = \"txt\"\n"
        let customize = try await started(shared, local: "disabled = [\"notes\", \"todo\"]\n"); defer { customize.cleanUp() }
        #expect(customize.model.newFile?.isBuiltIn == true && customize.model.newFile?.rows.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx"])
        await customize.model.customizeTemplates()
        #expect(text(customize) == shared, "every other Mac reads this file: Text Document and Markdown Document are not added to it")
        #expect(localText(customize).contains("id = \"txt\"") && localText(customize).contains("id = \"md\"") && customize.model.newFile?.isBuiltIn == false, "\(localText(customize))")
        #expect(customize.model.newFile?.rows.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx"] && customize.model.template("txt")?.entry?.target == .local)
        let make = try await started(shared, local: "disabled = [\"notes\", \"todo\"]\n"); defer { make.cleanUp() }
        #expect(await make.model.createTemplate(title: "Python Script", fileExtension: "py"))
        #expect(text(make) == shared && make.model.newFile?.rows.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx", "python-script"], "this Mac keeps the ones it showed, and gets the new one: \(localText(make))")
        #expect(ConfigParser.parse(text(make)).config.newFile.templates.map(\.id) == ["notes", "todo"])
    }

    @Test func aBuiltInPresetThatTheConfigWritesInAnInlineListIsTheConfigsAndIsNotCopiedToTheSharedFile() async throws {
        let mac = try await started(local: "preset = [{ id = \"review\", title = \"Private wording\", prompt = \"Only on this Mac: look at {files}.\" }]\n"); defer { mac.cleanUp() }
        let row = try #require(mac.model.preset("review"))
        #expect(row.origin == .customized && row.entry == nil && row.title == "Private wording", "it is not the built-in preset, and it has no place to edit it by")
        await mac.model.customizePreset("review")
        #expect(text(mac) == Self.sample, "the private wording is not written to the file that every Mac reads")
        #expect(localText(mac).hasPrefix("preset = [{") && !localText(mac).contains("[[preset]]"))
        // A new preset goes to the shared file, which has no inline list; where the list is written as a value in the file it would go to, it is refused and not appended after it.
        let inShared = try await started("preset = [{ id = \"mine\", title = \"Mine\", prompt = \"Look at {files}.\" }]\n\n" + Self.sample); defer { inShared.cleanUp() }
        let before = text(inShared)
        #expect(await inShared.model.createPreset(title: "Other", prompt: "Read {files}.") == false && inShared.model.editRefusal != nil, "a new entry is not appended to a list that is written as a value")
        #expect(text(inShared) == before)
    }

    @Test func aBuiltInPresetWhoseSharedEntryThisMacDropsIsCustomizedInThisMacsOwnFile() async throws {
        let shared = Self.sample.replacingOccurrences(of: "agents = [\"claude\"]", with: "agents = [\"claude\", \"codex\"]") + "\n[[preset]]\nid = \"review\"\ntitle = \"Strict review\"\nprompt = \"Review {files} strictly.\"\nagent = \"codex\"\n"
        let mac = try await started(shared, local: "disabled = [\"codex\"]\n"); defer { mac.cleanUp() }
        #expect(mac.model.preset("review")?.origin == .builtIn && mac.model.preset("review")?.hiddenInShared == true)
        await mac.model.customizePreset("review")
        #expect(text(mac) == shared, "the shared entry that every other Mac uses is left as it is")
        #expect(localText(mac).contains("[[preset]]\nid = \"review\"") && mac.model.preset("review")?.entry?.target == .local && mac.model.preset("review")?.origin == .customized, "\(localText(mac))")
        #expect(mac.model.editRefusal == nil)
    }

    @Test func anEmptiedFileNameIsTheDefaultOne() async throws {
        let mac = try await started(Self.sample + "\n[[new_file.template]]\nid = \"a\"\ntitle = \"A\"\nbase_name = \"notes\"\nextension = \"a\"\n"); defer { mac.cleanUp() }
        #expect(await mac.model.setTemplateBaseName("a", ""))
        #expect(mac.model.template("a")?.baseName == "untitled" && !text(mac).contains("base_name"), "\(text(mac))")
    }

    // MARK: A change that waits for another

    @Test func aChangeThatCouldNotWaitForTheWindowToBeFreeSaysSo() async throws {
        let mac = try await started(Self.sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n", patience: .milliseconds(100)); defer { mac.cleanUp() }
        mac.runner.answerSlowly(.seconds(3))
        let repair = Task { await mac.model.repair() }
        #expect(await mac.eventually { mac.model.isWorking })
        let before = text(mac)
        let done = await mac.model.setPresetTitle("mine", "Mine now")
        #expect(!done && text(mac) == before && mac.model.editRefusal?.notice == .busy && mac.model.editRefusal?.tab == .agents, "it is said under the editor it was made in")
        repair.cancel()
    }

    @Test func aChangeMadeWhileAnotherIsBeingWrittenWaitsForItAndIsMade() async throws {
        let mac = try await started(Self.sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n"); defer { mac.cleanUp() }
        mac.runner.answerSlowly(.milliseconds(60))
        let repair = Task { await mac.model.repair() }
        #expect(await mac.eventually { mac.model.isWorking })
        let done = await mac.model.setPresetTitle("mine", "Mine now")
        #expect(done && text(mac).contains("Mine now") && mac.model.editRefusal == nil, "a change waits for a write of a moment and is then made: \(text(mac))")
        await repair.value
    }
}

@Suite("The setup window's model: the forms of Copy Path and the Quick Actions")
@MainActor
struct SetupModelListTests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"
    private func text(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.configFile, encoding: .utf8)) ?? "" }
    private func localText(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.localConfigFile, encoding: .utf8)) ?? "" }

    private func started(_ config: String = SetupModelListTests.sample, local: String? = nil) async throws -> Mac {
        let mac = try Mac()
        try mac.writeConfig(config)
        if let local { try local.write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8) }
        await mac.model.refresh()
        return mac
    }

    @Test func theFormsOfCopyPathAreAddedMovedAndTakenOutAndTheFirstChangeWritesTheDefaultList() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(mac.model.copyPath?.offered.map(\.style) == Config.defaultCopyPathStyles && mac.model.copyPath?.list.usesDefaults == true)
        #expect(await mac.model.addChoice(.copyPath, "parent"))
        #expect(text(mac).contains("[copy_path]\nstyles = ["), "\(text(mac))")
        #expect(ConfigParser.parse(text(mac)).config.copyPathStyles == Config.defaultCopyPathStyles + [.parent], "the whole default list was written, and the form after it")
        #expect(mac.model.copyPath?.offered.last?.style == .parent && mac.model.copyPath?.list.usesDefaults == false)
        #expect(await mac.model.moveChoices(.copyPath, from: IndexSet(integer: 6), to: 0))
        #expect(mac.model.copyPath?.offered.first?.style == .parent)
        #expect(await mac.model.removeChoice(.copyPath, at: 2))
        #expect(mac.model.copyPath?.offered.map(\.style) == [.parent, .tilde, .gitRelative, .name, .shellEscaped, .aiMention])
        #expect(mac.model.configEdit?.key == "copy_path.styles" && mac.model.configEdit?.tab == .menu)
        await mac.model.undoEdit()
        #expect(mac.model.copyPath?.offered.first?.style == .parent && mac.model.copyPath?.offered.count == 7, "one Undo takes back the last change")
    }

    @Test func theTitleOfCopyPathIsSetAndTheEmptyOneTakesItOut() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(await mac.model.setCopyPathTitle("Paths"))
        #expect(text(mac).contains("[copy_path]\ntitle = \"Paths\"") && mac.model.copyPath?.title == "Paths")
        #expect(await mac.model.setCopyPathTitle("two\nlines") == false && mac.model.editRefusal?.key == "copy_path.title", "the config refuses a title that is not a plain name, and says so under this editor")
        #expect(await mac.model.setCopyPathTitle(""))
        #expect(mac.model.copyPath?.title == nil && !text(mac).contains("title ="))
    }

    @Test func theQuickActionsAreAddedAndTakenOutInTheFileThatDecidesThem() async throws {
        let mac = try await started(local: "[services]\nitems = [\"open.terminal\", \"agent.claude\"]\n"); defer { mac.cleanUp() }
        #expect(mac.model.quickActions?.rows.map(\.id) == ["open.terminal", "agent.claude"] && mac.model.quickActions?.list.usesDefaults == false)
        #expect(await mac.model.addChoice(.quickActions, "copy-path.name"))
        #expect(localText(mac).contains("items = [\"open.terminal\", \"agent.claude\", \"copy-path.name\"]") && text(mac) == Self.sample, "this Mac's own file writes the list, so the change goes there: \(localText(mac))")
        #expect(await mac.model.moveChoice(.quickActions, 3, by: -1) && mac.model.quickActions?.rows.map(\.id) == ["open.terminal", "copy-path.name", "agent.claude"])
        #expect(await mac.model.moveChoice(.quickActions, 1, by: 1) && mac.model.quickActions?.rows.map(\.id) == ["copy-path.name", "open.terminal", "agent.claude"])
        #expect(await mac.model.moveChoice(.quickActions, 1, by: -1) == false, "the first one cannot go up")
        #expect(await mac.model.removeChoice(.quickActions, at: 1))
        #expect(mac.model.quickActions?.rows.map(\.id) == ["open.terminal", "agent.claude"])
        await mac.model.undoEdit()
        #expect(mac.model.quickActions?.rows.map(\.id) == ["copy-path.name", "open.terminal", "agent.claude"])
    }

    @Test func theFirstChangeOfTheQuickActionsGoesToThisMacsFileWhenItsDefaultIsNotTheOthersAndOtherwiseToTheSharedOne() async throws {
        let shared = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\", \"codex\"]\n"
        let mac = try await started(shared, local: "disabled = [\"claude\"]\n"); defer { mac.cleanUp() }
        #expect(mac.model.quickActions?.rows.map(\.id).contains("agent.claude") == false && mac.model.quickActions?.list.firstChangeTarget == .local)
        #expect(await mac.model.addChoice(.quickActions, "copy-path.name"))
        #expect(text(mac) == shared, "the shared file, which the other Macs read, did not take this Mac's list")
        #expect(localText(mac).contains("services") && localText(mac).contains("copy-path.name") && !localText(mac).contains("agent.claude"), Comment(rawValue: localText(mac)))
        #expect(ConfigStore.sharedConfig(paths: mac.paths).serviceItems == nil, "the others keep the default, with Claude Code in it")
        // With nothing turned off the two are the same, and the first change goes where the setting is decided.
        let plain = try await started(shared); defer { plain.cleanUp() }
        #expect(plain.model.quickActions?.list.firstChangeTarget == nil)
        #expect(await plain.model.addChoice(.quickActions, "copy-path.name") && text(plain).contains("copy-path.name") && !FileManager.default.fileExists(atPath: plain.paths.localConfigFile.path))
    }

    @Test func theAddQuickActionMenuDoesNotOfferAnAgentThisMacTurnsOff() async throws {
        let mac = try await started("[general]\nterminal = \"ghostty\"\nagents = [\"claude\", \"codex\"]\n", local: "disabled = [\"claude\"]\n"); defer { mac.cleanUp() }
        let offered = mac.model.quickActions?.choices.map(\.id) ?? []
        #expect(!offered.isEmpty && !offered.contains { $0.hasPrefix("agent.claude") }, Comment(rawValue: "\(offered)"))
        let plain = try await started("[general]\nterminal = \"ghostty\"\nagents = [\"claude\", \"codex\"]\n\n[services]\nitems = [\"open.terminal\"]\n"); defer { plain.cleanUp() }
        #expect(plain.model.quickActions?.choices.map(\.id).contains("agent.claude") == true, "an agent that is not turned off is offered")
        #expect(mac.model.quickActions?.list.isExact == true)
    }

    @Test func theQuickActionsFollowAChangeMadeInTheWindowAtOnce() async throws {
        // They were left as the last Install or Repair made them, and the check said they differ until the person pressed it again: an agent put in the menu had no Quick Action.
        // English to start with, so that German renames them on a Mac of any language.
        let mac = try await started("[general]\nlanguage = \"en\"\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"); defer { mac.cleanUp() }
        await mac.model.repair()
        let installer = Installer(home: mac.home)
        let before = installer.installedServices().count
        #expect(mac.model.check(.services)?.status == .ok, "what Install or Repair made is what the config asks for")
        #expect(await mac.model.addChoice(.quickActions, "copy-path.name"))
        #expect(mac.model.check(.services)?.status == .ok, "the window wrote them again: \(mac.model.check(.services)?.detail?.english() ?? "")")
        #expect(installer.installedServices().count == before + 1)
        let english = Set(installer.installedServices().map(\.lastPathComponent))
        await mac.model.setLanguage("de")
        #expect(mac.model.check(.services)?.status == .ok, "their names follow the language")
        #expect(Set(installer.installedServices().map(\.lastPathComponent)) != english, "they are named in German now")
    }

    @Test func whereThereAreNoQuickActionsYetAChangeMakesNone() async throws {
        let mac = try Mac(); defer { mac.cleanUp() }
        try mac.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        await mac.model.refresh()
        #expect(await mac.model.addChoice(.quickActions, "copy-path.name"))
        #expect(Installer(home: mac.home).installedServices().isEmpty, "setting up is the person's to start")
    }

    @Test func anActionListedTwiceIsOneRowWithOneId() async throws {
        let mac = try await started(local: "[services]\nitems = [\"open.terminal\", \"agent.claude\", \"open.terminal\"]\n"); defer { mac.cleanUp() }
        #expect(mac.model.quickActions?.rows.map(\.id) == ["open.terminal", "agent.claude"])
    }

    @Test func aListThatChangedUnderTheEditIsNotChangedInPlaceOfAnother() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        _ = try ConfigService(paths: mac.paths, environment: [:]).apply(.set("copy_path.styles", .strings(["name"])), actor: .cli)
        let before = text(mac)
        #expect(await mac.model.removeChoice(.copyPath, at: 1) == false, "the window showed the default list, and the file writes another one now")
        #expect(text(mac) == before && mac.model.notice == .listChanged)
        #expect(mac.model.copyPath?.offered.map(\.style) == [.name], "and it reads again")
    }

    @Test func anIdThatTheConfigDoesNotReadAsAnActionIsNotAnEditableList() async throws {
        let mac = try await started(Self.sample + "\n[services]\nitems = [\"open.terminal\", \"nonsense\"]\n"); defer { mac.cleanUp() }
        #expect(mac.model.quickActions?.list.isExact == false)
        let before = text(mac)
        #expect(await mac.model.addChoice(.quickActions, "copy-path.name") == true && text(mac) == before, "nothing is changed by place: the page says the list can only be changed as text")
    }
}

@Suite("The setup window's model: the routes the window takes, and what review 24 found in them")
@MainActor
struct SetupModelRouteTests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"
    private static let withVariant = sample + "\n[[agent.claude.variant]]\nid = \"a\"\ntitle = \"A\"\narguments = [\"--a\", \"--b\", \"--c\"]\n"
    private static let switchedOn = "[general]\nagents = [\"claude\", \"goose\"]\nbypass_permissions = true\n"
    private func text(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.configFile, encoding: .utf8)) ?? "" }

    private func started(_ config: String = SetupModelRouteTests.sample, local: String? = nil, patience: Duration? = nil) async throws -> Mac {
        let mac = try Mac(patience: patience)
        try mac.writeConfig(config)
        if let local { try local.write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8) }
        await mac.model.refresh()
        return mac
    }

    // MARK: The lists of arguments, as the window changes them

    @Test func theAgentsOwnArgumentsAreChangedThroughTheListTheWindowShows() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        let owner = ArgumentListOwner.agent("claude")
        #expect(await mac.model.addArgument(owner, "--a"))
        #expect(await mac.model.addArgument(owner, "--b"))
        #expect(mac.model.argumentList(of: owner)?.items == ["--a", "--b"])
        #expect(await mac.model.setArgument(owner, at: 1, from: "--a", to: "--aa"))
        #expect(await mac.model.moveArgument(owner, 1, by: 1))
        #expect(mac.model.agentOptions("claude")?.args == ["--b", "--aa"])
        #expect(await mac.model.moveArguments(owner, from: IndexSet(integer: 1), to: 0))
        #expect(mac.model.agentOptions("claude")?.args == ["--aa", "--b"])
        #expect(await mac.model.removeArgument(owner, at: 1))
        #expect(mac.model.agentOptions("claude")?.args == ["--b"])
    }

    @Test func aFieldOfAStartOptionThatShowedAnotherArgumentChangesNothing() async throws {
        let mac = try await started(Self.withVariant); defer { mac.cleanUp() }
        let owner = ArgumentListOwner.variant(agent: "claude", id: "a")
        #expect(await mac.model.removeArgument(owner, at: 1))
        let before = text(mac)
        _ = await mac.model.setArgument(owner, at: 2, from: "--b", to: "--bee")
        #expect(text(mac) == before && mac.model.variant("claude", "a")?.arguments.items == ["--b", "--c"], "`--c` was not typed over")
    }

    @Test func anArgumentOfAStartOptionMovesDownAndNotPastAnEnd() async throws {
        let mac = try await started(Self.withVariant); defer { mac.cleanUp() }
        let owner = ArgumentListOwner.variant(agent: "claude", id: "a")
        #expect(await mac.model.moveArgument(owner, 1, by: 1))
        #expect(mac.model.variant("claude", "a")?.arguments.items == ["--b", "--a", "--c"])
        #expect(await mac.model.moveArgument(owner, 3, by: 1) == false)
        #expect(await mac.model.moveArgument(owner, 1, by: -1) == false)
        #expect(mac.model.variant("claude", "a")?.arguments.items == ["--b", "--a", "--c"])
    }

    @Test func aSecondClickOnTheSameMinusOfAStartOptionTakesOutOneArgumentAndOneMoveIsOneMove() async throws {
        let mac = try await started(Self.withVariant); defer { mac.cleanUp() }
        let owner = ArgumentListOwner.variant(agent: "claude", id: "a")
        async let first = mac.model.removeArgument(owner, at: 1)
        async let second = mac.model.removeArgument(owner, at: 1)
        _ = await (first, second)
        #expect(mac.model.variant("claude", "a")?.arguments.items == ["--b", "--c"], "the second click was meant for the argument that was at that place when it was made")
        async let down = mac.model.moveArgument(owner, 1, by: 1)
        async let again = mac.model.moveArgument(owner, 1, by: 1)
        _ = await (down, again)
        #expect(mac.model.variant("claude", "a")?.arguments.items == ["--c", "--b"], "one move, not two")
    }

    @Test func anUndoIsRefusedWhenSomethingElseChangedTheSettingAndChangedItBack() async throws {
        let mac = try await started(Self.sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n"); defer { mac.cleanUp() }
        #expect(await mac.model.setPresetTitle("mine", "First"))
        let service = ConfigService(paths: mac.paths, environment: [:])
        _ = try service.apply(.set("preset.1.title", .string("Second")), actor: .cli)
        _ = try service.apply(.set("preset.1.title", .string("First")), actor: .cli)
        let before = text(mac)
        await mac.model.undoEdit()
        #expect(text(mac) == before && mac.model.notice == .undoRefused, "the file reads as the window left it, but the newest change is somebody else's and replaced other text")
    }

    @Test func aDoubleClickOnARemoveButtonTakesOutOnlyTheEntryThePageShowedWhenBothFilesWriteTheId() async throws {
        let preset = "[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n"
        let template = "[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \"t\"\n"
        let variant = "[[agent.claude.variant]]\nid = \"a\"\ntitle = \"A\"\narguments = [\"--a\"]\n"
        let mac = try await started(Self.sample + "\n" + preset.replacingOccurrences(of: "Mine", with: "Shared") + "\n" + template.replacingOccurrences(of: "\"T\"", with: "\"Shared\"") + "\n" + variant.replacingOccurrences(of: "\"A\"", with: "\"Shared\""),
                                    local: preset + "\n" + template + "\n" + variant, patience: .seconds(30)); defer { mac.cleanUp() }
        #expect(mac.model.preset("mine")?.entry?.target == .local && mac.model.template("t")?.entry?.target == .local && mac.model.variant("claude", "a")?.entry.target == .local)
        async let p1: Void = mac.model.removePreset("mine"); async let p2: Void = mac.model.removePreset("mine")
        async let t1: Void = mac.model.removeTemplate("t"); async let t2: Void = mac.model.removeTemplate("t")
        async let v1: Void = mac.model.removeVariant("claude", "a"); async let v2: Void = mac.model.removeVariant("claude", "a")
        _ = await (p1, p2, t1, t2, v1, v2)
        let shared = text(mac)
        #expect(shared.contains("title = \"Shared\"\nprompt") && shared.contains("id = \"t\"") && shared.contains("id = \"a\""), "the entries that every Mac reads are all still there: \(shared)")
    }

    // MARK: A change that cannot wait says so, under its own editor

    @Test func everyChangeThatCouldNotWaitSaysSoUnderItsOwnEditor() async throws {
        let config = Self.withVariant + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n\n[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \"t\"\n"
            + "\n[agent.own]\ncommand = \"own\"\n"
        let mac = try await started(config.replacingOccurrences(of: "agents = [\"claude\"]", with: "agents = [\"claude\", \"own\"]"), patience: .milliseconds(50)); defer { mac.cleanUp() }
        mac.runner.answerSlowly(.seconds(60))
        let repair = Task { await mac.model.repair() }
        #expect(await mac.eventually { mac.model.isWorking })
        func said(_ tab: SetupTab, _ key: String) -> Bool {
            mac.model.editRefusal?.notice == .busy && mac.model.editRefusal?.tab == tab && mac.model.editRefusal?.key == key && mac.model.notice == .busy
        }
        let before = text(mac)
        _ = await mac.model.setVariantTitle("claude", "a", "Aye")
        #expect(said(.agents, "agent.claude.variant.a"), "a start option's title")
        _ = await mac.model.createVariant(agent: "claude", title: "New")
        #expect(said(.agents, "agent.claude.variant"), "a new start option")
        _ = await mac.model.setTemplateTitle("t", "Tee")
        #expect(said(.menu, "new_file.template.t"), "a template's title")
        _ = await mac.model.createPreset(title: "New", prompt: "Look at {files}.")
        #expect(said(.agents, "preset"), "a new preset")
        await mac.model.removePreset("mine")
        #expect(said(.agents, "preset.mine"), "taking a preset out")
        _ = await mac.model.createAgent(name: "Another", command: "another")
        #expect(said(.agents, GeneralSettingsState.agentsKey), "a new agent")
        await mac.model.removeAgent("own")
        #expect(said(.agents, "agent.own.command"), "taking an agent out")
        #expect(text(mac) == before, "nothing was written")
        repair.cancel()
    }

    @Test func aChangeThatIsCalledOffWhileItWaitsIsNotSaidToBeBusyAndDoesNotSpinForTheRest() async throws {
        let mac = try await started(Self.sample + "\n[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \"t\"\n"); defer { mac.cleanUp() }
        mac.runner.answerSlowly(.seconds(60))
        let repair = Task { await mac.model.repair() }
        #expect(await mac.eventually { mac.model.isWorking })
        let typing = Task { await mac.model.setTemplateContents("t", "x", announcing: false) }
        try await Task.sleep(for: .milliseconds(100))
        typing.cancel()
        let started = ContinuousClock.now
        let done = await typing.value
        // The window's patience in a test is 30 seconds: stopping within 5 tells calling off from waiting out the rest, on a machine that runs every suite at once.
        #expect(done == false && ContinuousClock.now - started < .seconds(5), "it stopped waiting when it was called off")
        #expect(mac.model.editRefusal == nil && mac.model.notice != .busy, "the window was not too busy: the typing went on")
        repair.cancel()
    }

    @Test func aRefusalGoesWithTheNextChangeThatIsMade() async throws {
        let mac = try await started(Self.sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n"); defer { mac.cleanUp() }
        #expect(await mac.model.setPresetPrompt("mine", "line\nbreak {files}") == false && mac.model.editRefusal != nil)
        #expect(await mac.model.setPresetTitle("mine", "Mine now"))
        #expect(mac.model.editRefusal == nil && mac.model.configEdit != nil)
    }

    @Test func aChangeThatChangedNothingMakesNoNote() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        let done = await mac.model.edit([.set("general.terminal", .string("ghostty"))], deciding: "general.terminal", saying: .appEditSaved, on: .overview)
        #expect(done && mac.model.configEdit == nil, "a note of a change that was not made would undo somebody else's")
    }

    @Test func removingAStartOptionWhileItsTitleIsWrittenIsNotDropped() async throws {
        let mac = try await started(Self.withVariant); defer { mac.cleanUp() }
        async let title = mac.model.setVariantTitle("claude", "a", "Aye")
        async let removal: Void = mac.model.removeVariant("claude", "a")
        _ = await (title, removal)
        #expect(mac.model.variant("claude", "a") == nil && !text(mac).contains("id = \"a\""), "\(text(mac))")
    }

    // MARK: Where a start option that was made is, and what says so

    @Test func theStartOptionThatWasMadeIsTheOneTheFormOpens() async throws {
        let mac = try await started(local: "[[agent.claude.variant]]\nid = \"b\"\ntitle = \"B\"\n"); defer { mac.cleanUp() }
        let made = await mac.model.createVariant(agent: "claude", title: "Use Opus")
        #expect(made == "use-opus")
        #expect(mac.model.agentOptions("claude")?.variants.last?.id == "b", "this Mac's own start option comes after the shared one that was made, so the last of the list is not the one made")
        #expect(made.flatMap { mac.model.variant("claude", $0) }?.title == "Use Opus")
    }

    @Test func theNotesOfStartOptionsAreSaidOnThePagesOfTheAgent() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(await mac.model.createVariant(agent: "claude", title: "Use Opus") != nil)
        #expect(mac.model.configEdit?.tab == .agents && mac.model.configEdit?.key.hasPrefix("agent.claude.") == true)
        #expect(await mac.model.setVariantTitle("claude", "use-opus", "Opus"))
        #expect(mac.model.configEdit?.tab == .agents && mac.model.configEdit?.key.hasPrefix("agent.claude.") == true)
    }

    @Test func aReadThatBeganBeforeAnEditDoesNotPutTheOldStartOptionsBack() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        mac.model.select(.agents)
        var stale = try #require(mac.model.snapshot)
        stale.readAt = .now
        try await Task.sleep(for: .milliseconds(5))
        #expect(await mac.model.createVariant(agent: "claude", title: "Use Opus") != nil)
        mac.model.openAgentOptions("claude")
        mac.model.openVariant(VariantRef(agent: "claude", id: "use-opus"))
        mac.model.apply(stale)
        #expect(mac.model.variant("claude", "use-opus") != nil && mac.model.variantDetail == VariantRef(agent: "claude", id: "use-opus"))
    }

    // MARK: A block of text that rests, and a change that the person said no to

    @Test func aBlockThatRestsIsWrittenWithoutBeingAnnouncedAndTheChangeThatEndsItIs() async throws {
        let mac = try await started(Self.sample + "\n[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \"t\"\n"); defer { mac.cleanUp() }
        #expect(await mac.model.setTemplateContents("t", "one", announcing: false))
        #expect(mac.model.template("t")?.contents == "one" && mac.model.configEdit != nil, "it is written, and the note that offers Undo is there")
        #expect(mac.model.lastAnnouncement == nil, "the person is still typing: VoiceOver is not interrupted")
        #expect(await mac.model.setTemplateContents("t", "two"))
        #expect(mac.model.lastAnnouncement != nil, "the change that ends the typing is told")
        #expect(await mac.model.setTemplateTitle("t", "Tee"))
        #expect(mac.model.lastAnnouncement == Localizer.system.render(.appAgentEdited("T")), "any other change is announced")
    }

    @Test func theAnswerToAHeldChangeIsTold_ANoAndAYesThatWasMade_AndTheAlertClosingIsNeitherOfThem() async throws {
        let mac = try await started(Self.switchedOn); defer { mac.cleanUp() }
        let before = text(mac)
        #expect(await mac.model.setAgentBypassArgument("goose", "--yolo") == false && mac.model.pendingLoosening != nil)
        let token = mac.model.fieldAnswerToken
        mac.model.cancelLoosening()
        #expect(mac.model.pendingLoosening == nil && mac.model.fieldAnswerToken == token, "the alert closing is not the person's no")
        #expect(await mac.model.setAgentBypassArgument("goose", "--yolo") == false && mac.model.pendingLoosening != nil)
        mac.model.declineLoosening()
        #expect(mac.model.pendingLoosening == nil && mac.model.fieldAnswerToken == token + 1 && text(mac) == before, "a no is told")
        #expect(await mac.model.setAgentBypassArgument("goose", "--yolo") == false && mac.model.pendingLoosening != nil)
        await mac.model.confirmLoosening()
        #expect(mac.model.fieldAnswerToken == token + 2, "a yes that was made is told, so that the field that raised it does not make the change again")
        #expect(text(mac).contains("--yolo"))
    }
}

@Suite("The setup window's model: the apps the config adds")
@MainActor
struct SetupModelAppsTests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"
    private static let withApps = sample + "\n[[app]]\nid = \"pulsar\"\nname = \"Pulsar\"\nbundle_id = \"dev.pulsar-edit.pulsar\"\nrole = \"editor\"\n"
        + "\n[[app]]\nid = \"tabby\"\nname = \"Tabby\"\nbundle_id = \"org.tabby\"\nrole = \"terminal\"\nopen_args = [\"/usr/bin/open\", \"-a\", \"{app}\", \"{dir}\"]\n"
    private func text(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.configFile, encoding: .utf8)) ?? "" }
    private func localText(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.localConfigFile, encoding: .utf8)) ?? "" }

    private func started(_ config: String = SetupModelAppsTests.sample, local: String? = nil, patience: Duration? = nil) async throws -> Mac {
        let mac = try Mac(patience: patience)
        try mac.writeConfig(config)
        if let local { try local.write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8) }
        await mac.model.refresh()
        return mac
    }

    /// A folder that is an application as far as its `Info.plist` goes.
    private func application(_ name: String, bundleID: String?, in mac: Mac) throws -> URL {
        let app = mac.home.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleName": name]
        if let bundleID { info["CFBundleIdentifier"] = bundleID }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    @Test func anAppIsAddedChangedAndTakenOutAndEachChangeCanBeUndone() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(mac.model.apps?.rows.isEmpty == true)
        let id = await mac.model.createApp(name: "Pulsar", bundleID: "dev.pulsar-edit.pulsar", role: .editor)
        #expect(id == "pulsar")
        #expect(text(mac).contains("[[app]]\nid = \"pulsar\"\nname = \"Pulsar\"\nbundle_id = \"dev.pulsar-edit.pulsar\"\nrole = \"editor\"\n"), "\(text(mac))")
        #expect(mac.model.app("pulsar")?.role == .editor && mac.model.app("pulsar")?.entry == EntryLocation(target: .shared, position: 1))
        #expect(mac.model.configEdit?.tab == .overview && mac.model.configEdit?.key == "app.pulsar")
        #expect(await mac.model.setAppName("pulsar", "Pulsar Edit"))
        #expect(mac.model.configEdit?.tab == .overview && mac.model.configEdit?.key == "app.pulsar", "the note of a change is said on the Overview, under the apps")
        #expect(await mac.model.setAppRole("pulsar", .general))
        #expect(mac.model.app("pulsar")?.name == "Pulsar Edit" && mac.model.app("pulsar")?.role == .general)
        await mac.model.undoEdit()
        #expect(mac.model.app("pulsar")?.role == .editor, "Undo takes the role back")
        await mac.model.removeApp("pulsar")
        #expect(mac.model.apps?.rows.isEmpty == true && !text(mac).contains("[[app]]"))
        #expect(mac.model.configEdit?.tab == .overview && mac.model.configEdit?.key == "app.pulsar")
        await mac.model.undoEdit()
        #expect(mac.model.app("pulsar")?.name == "Pulsar Edit")
    }

    @Test func aTerminalThatTheConfigStartsThroughTemplatesKeepsItsRoleAndItsTemplates() async throws {
        let mac = try await started(Self.withApps); defer { mac.cleanUp() }
        #expect(mac.model.app("tabby")?.usesTemplates == true)
        let before = text(mac)
        #expect(await mac.model.setAppRole("tabby", .editor) == true && text(mac) == before, "nothing to change is made, and nothing is written")
        #expect(await mac.model.setAppName("tabby", "Tabby 2"))
        #expect(text(mac).contains("open_args = [\"/usr/bin/open\", \"-a\", \"{app}\", \"{dir}\"]") && text(mac).contains("name = \"Tabby 2\""))
    }

    @Test func anAppThatThisMacsFileWritesIsChangedThereAndANewOneGoesToTheSharedFile() async throws {
        let mac = try await started(local: "[[app]]\nid = \"nova\"\nname = \"Nova Editor\"\nbundle_id = \"com.example.NovaEditor\"\nrole = \"editor\"\n"); defer { mac.cleanUp() }
        #expect(mac.model.app("nova")?.entry?.target == .local)
        #expect(await mac.model.setAppName("nova", "Nova 2"))
        #expect(localText(mac).contains("name = \"Nova 2\"") && text(mac) == Self.sample)
        #expect(await mac.model.createApp(name: "Pulsar", bundleID: "dev.pulsar-edit.pulsar", role: .editor) == "pulsar")
        #expect(text(mac).contains("id = \"pulsar\"") && !localText(mac).contains("pulsar"))
        #expect(mac.model.app("nova")?.entry?.target == .local && mac.model.app("pulsar")?.entry?.target == .shared)
    }

    @Test func aNewAppTakesNoIdThatAFileHasEvenWhenTheWindowDoesNotShowItYet() async throws {
        let mac = try await started(local: "disabled = [\"pulsar\"]\n"); defer { mac.cleanUp() }
        #expect(await mac.model.createApp(name: "Pulsar", bundleID: "dev.pulsar-edit.pulsar", role: .editor) == "pulsar-2", "the id that this Mac turns off is in use")
        let zed = await mac.model.createApp(name: "Zed Nightly", bundleID: "dev.zed.Zed-Nightly", role: .editor)
        #expect(zed == "zed-nightly" && mac.model.app("zed-nightly") != nil)
        #expect(await mac.model.createApp(name: "Zed", bundleID: "dev.zed.ZedMine", role: .editor) == "zed-2", "a built-in app is not replaced by accident")
    }

    @Test func theChosenApplicationIsReadAndOneThatIsThereAlreadyOrHasNoIdentifierIsSaid() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        let pulsar = try application("Pulsar", bundleID: "dev.pulsar-edit.pulsar", in: mac)
        #expect(mac.model.pickedApp(at: pulsar) == AppBundleInfo(bundleID: "dev.pulsar-edit.pulsar", name: "Pulsar") && mac.model.notice == nil)
        let ghostty = try application("Ghostty Copy", bundleID: "com.mitchellh.ghostty", in: mac)
        #expect(mac.model.pickedApp(at: ghostty) == nil && mac.model.notice == .appAlreadyAvailable("Ghostty"), "the app that Right Here offers already is said, and not added twice")
        let bare = try application("Bare", bundleID: nil, in: mac)
        #expect(mac.model.pickedApp(at: bare) == nil && mac.model.notice == .appNotFound("Bare"))
        #expect(mac.model.pickedApp(at: mac.home.appendingPathComponent("Missing.app")) == nil && mac.model.notice == .appNotFound("Missing"))
        _ = await mac.model.createApp(name: "Pulsar", bundleID: "dev.pulsar-edit.pulsar", role: .editor)
        #expect(mac.model.pickedApp(at: pulsar) == nil && mac.model.notice == .appAlreadyAvailable("Pulsar"), "an app that the config added is there already too")
    }

    @Test func theAppsPageClosesWhenTheAppIsTakenOutOrTheSectionIsLeft() async throws {
        let mac = try await started(Self.withApps); defer { mac.cleanUp() }
        mac.model.openApp("pulsar")
        await mac.model.removeApp("pulsar")
        #expect(mac.model.appDetail == nil, "the page of an app that is gone is not left open")
        mac.model.openApp("tabby")
        mac.model.select(.agents)
        #expect(mac.model.appDetail == nil)
        mac.model.select(.overview)
        mac.model.openApp("tabby")
        _ = try service(mac).apply(.removeEntry(at: 1, from: "app"), actor: .cli)
        await mac.model.refresh()
        #expect(mac.model.appDetail == nil && mac.model.apps?.rows.isEmpty == true, "something else took it out, and the window read again")
    }

    private func service(_ mac: Mac) -> ConfigService { ConfigService(paths: mac.paths, environment: [:]) }

    @Test func aBuiltInAppThatThisMacTurnsOffIsSaidUnderTheAppsAndNeverAddedAgain() async throws {
        let mac = try await started(local: "disabled = [\"terminal\"]\n"); defer { mac.cleanUp() }
        let terminal = try application("Terminal Copy", bundleID: "com.apple.Terminal", in: mac)
        #expect(mac.model.pickedApp(at: terminal) == nil)
        #expect(mac.model.notice == .appTurnedOff("Terminal") && mac.model.editRefusal == EditRefusal(notice: .appTurnedOff("Terminal"), tab: .overview, key: "app"), "said under the apps, where Add App… was pressed")
        let before = text(mac)
        #expect(await mac.model.createApp(name: "Terminal", bundleID: "com.apple.Terminal", role: .editor) == nil && text(mac) == before, "not as an editor, which would hand a terminal files")
        let pulsar = try application("Pulsar", bundleID: "dev.pulsar-edit.pulsar", in: mac)
        #expect(mac.model.pickedApp(at: pulsar) != nil && mac.model.editRefusal == nil, "the next choice that can be added takes the note away")
    }

    @Test func aWindowThatHasNotReadAgainDoesNotAddTheSameAppTwiceOrAnApplicationItCannotUse() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        let pulsar = try application("Pulsar", bundleID: "dev.pulsar-edit.pulsar", in: mac)
        #expect(mac.model.pickedApp(at: pulsar) != nil)
        // Something else adds the same app after the window read the config.
        _ = try service(mac).apply(.addEntry(to: "app", fields: [ConfigField("id", .string("pulsar")), ConfigField("name", .string("Pulsar")), ConfigField("bundle_id", .string("dev.pulsar-edit.pulsar"))], at: nil), actor: .cli)
        let before = text(mac)
        #expect(await mac.model.createApp(name: "Pulsar", bundleID: "dev.pulsar-edit.pulsar", role: .editor) == nil && text(mac) == before)
        #expect(mac.model.editRefusal?.notice == .appAlreadyAvailable("Pulsar") && mac.model.editRefusal?.key == "app", "the files say it is there, though the window has not read them")
        let odd = try application("Odd", bundleID: "com.example.odd app", in: mac)
        #expect(mac.model.pickedApp(at: odd) == nil && mac.model.editRefusal?.notice == .appNotFound("Odd"), "an identifier that the config would refuse is said now, not by a button that does nothing")
    }

    @Test func theRoleOfATerminalThatComesWithRightHereIsNotChangedByTheWindow() async throws {
        let mac = try await started(Self.sample + "\n[[app]]\nid = \"my-iterm\"\nname = \"My iTerm\"\nbundle_id = \"com.googlecode.iterm2\"\nrole = \"terminal\"\n"); defer { mac.cleanUp() }
        #expect(mac.model.app("my-iterm")?.isKnownTerminal == true)
        let before = text(mac)
        #expect(await mac.model.setAppRole("my-iterm", .editor) == true && text(mac) == before, "nothing to change is made: it would hand a terminal files")
    }

    @Test func aNewAppTemplateOrAgentTakesNoIdThatAnotherKindHasBecauseDisabledNamesAllThree() async throws {
        let mac = try await started(Self.sample + "\n[[new_file.template]]\nid = \"notes\"\ntitle = \"Notes\"\nextension = \"md\"\n"); defer { mac.cleanUp() }
        #expect(await mac.model.createApp(name: "Claude", bundleID: "com.anthropic.claudefordesktop", role: .general) == "claude-2", "an agent's id")
        #expect(await mac.model.createApp(name: "Notes", bundleID: "com.example.notes", role: .general) == "notes-2", "a template's id")
        #expect(await mac.model.createTemplate(title: "Zed", fileExtension: "txt") == true)
        #expect(mac.model.template("zed-2") != nil && mac.model.template("zed") == nil, "a template called like a built-in app takes another id")
        #expect(await mac.model.createAgent(name: "Notes", command: "notes") == true && mac.model.agentOptions("notes-3") != nil && mac.model.agentOptions("notes") == nil && mac.model.agentOptions("notes-2") == nil,
                "and an agent called like a template and like the app made above")
    }

    @Test func aDoubleClickOnRemoveAppTakesOutOnlyThisMacsEntry() async throws {
        let entry = "[[app]]\nid = \"pulsar\"\nname = \"Pulsar here\"\nbundle_id = \"dev.pulsar-edit.pulsar\"\nrole = \"editor\"\n"
        let mac = try await started(Self.sample + entry.replacingOccurrences(of: "Pulsar here", with: "Pulsar shared"), local: entry); defer { mac.cleanUp() }
        #expect(mac.model.app("pulsar")?.entry?.target == .local)
        async let first: Void = mac.model.removeApp("pulsar")
        async let second: Void = mac.model.removeApp("pulsar")
        _ = await (first, second)
        #expect(text(mac).contains("Pulsar shared"), "the second click was for this Mac's entry, which is gone: the shared one, which every Mac reads, stays")
        #expect(mac.model.notice == .listChanged)
    }

    @Test func aReadThatBeganBeforeAnEditDoesNotPutTheOldAppsBack() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        var stale = try #require(mac.model.snapshot)
        stale.readAt = .now
        try await Task.sleep(for: .milliseconds(5))
        #expect(await mac.model.createApp(name: "Pulsar", bundleID: "dev.pulsar-edit.pulsar", role: .editor) == "pulsar")
        mac.model.openApp("pulsar")
        mac.model.apply(stale)
        #expect(mac.model.app("pulsar") != nil && mac.model.appDetail == "pulsar", "the apps that were read before the edit are not put back, and the page of the new app stays open")
    }

    @Test func aChangeOfAnAppThatCouldNotWaitSaysSoUnderTheOverview() async throws {
        let mac = try await started(Self.withApps, patience: .milliseconds(50)); defer { mac.cleanUp() }
        mac.runner.answerSlowly(.seconds(60))
        let repair = Task { await mac.model.repair() }
        #expect(await mac.eventually { mac.model.isWorking })
        let before = text(mac)
        #expect(await mac.model.setAppName("pulsar", "Other") == false)
        #expect(mac.model.editRefusal?.notice == .busy && mac.model.editRefusal?.tab == .overview && mac.model.editRefusal?.key == "app.pulsar")
        #expect(await mac.model.createApp(name: "New", bundleID: "com.example.New", role: .editor) == nil && mac.model.editRefusal?.key == "app")
        await mac.model.removeApp("pulsar")
        #expect(mac.model.editRefusal?.key == "app.pulsar" && text(mac) == before)
        repair.cancel()
    }

    @Test func anAppCannotBeAddedTwiceOrFromWhatTheConfigWouldRefuse() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        #expect(await mac.model.createApp(name: "", bundleID: "com.example.A", role: .editor) == nil)
        #expect(await mac.model.createApp(name: "A", bundleID: "not a bundle id", role: .editor) == nil)
        #expect(await mac.model.createApp(name: "Ghostty", bundleID: "com.mitchellh.ghostty", role: .terminal) == nil)
        #expect(await mac.model.createApp(name: "Line\nbreak", bundleID: "com.example.Break", role: .editor) == nil && mac.model.editRefusal != nil, "the config refuses a name with a line break, and says so")
        #expect(!text(mac).contains("[[app]]"))
    }
}

@Suite("The setup window's model: what review 25 found the model tests left open")
@MainActor
struct SetupModelGapTests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"
    private func text(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.configFile, encoding: .utf8)) ?? "" }
    private func localText(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.localConfigFile, encoding: .utf8)) ?? "" }
    private func service(_ mac: Mac) -> ConfigService { ConfigService(paths: mac.paths, environment: [:]) }

    private func started(_ config: String = SetupModelGapTests.sample, local: String? = nil, patience: Duration? = nil) async throws -> Mac {
        let mac = try Mac(patience: patience)
        try mac.writeConfig(config)
        if let local { try local.write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8) }
        await mac.model.refresh()
        return mac
    }

    // MARK: The lists of choices (stage 8)

    /// Kills L1: `choiceList(.copyPath)` decides the lock of the Copy Path panel and the bounds of its Move Up and Move Down.
    @Test func theCopyPathPanelIsLockedAndMovedByItsOwnList() async throws {
        let mac = try await started(Self.sample + "\n[services]\nitems = [\"open.terminal\", \"nonsense\"]\n"); defer { mac.cleanUp() }
        #expect(mac.model.choiceList(.quickActions)?.isExact == false)
        #expect(mac.model.choiceList(.copyPath)?.isExact == true, "the Quick Actions' list that cannot be changed by place does not lock Copy Path")
        #expect(mac.model.choiceList(.copyPath)?.items == Config.defaultCopyPathStyles.map(\.rawValue))
        let before = text(mac)
        #expect(await mac.model.moveChoice(.copyPath, Config.defaultCopyPathStyles.count, by: 1) == false, "the last form cannot go down")
        #expect(text(mac) == before)
    }

    /// Kills L4: a check of a form while another change is being written waits for it, as a change that names its setting does.
    @Test func aFormCheckedWhileTheTitleIsWrittenIsAdded() async throws {
        let mac = try await started(Self.sample); defer { mac.cleanUp() }
        async let title = mac.model.setCopyPathTitle("Paths")
        async let added = mac.model.addChoice(.copyPath, "parent")
        let (titled, checked) = await (title, added)
        #expect(titled && checked)
        #expect(mac.model.copyPath?.title == "Paths" && mac.model.copyPath?.offered.last?.style == .parent, "\(text(mac))")
    }

    /// Kills L9: a change by place is worked out from what the page showed; a second click on the same check does not take out the form that moved up under it.
    @Test func aSecondClickOnTheSameCheckTakesOutOneForm() async throws {
        let mac = try await started(Self.sample); defer { mac.cleanUp() }
        async let first = mac.model.removeChoice(.copyPath, at: 1)
        async let second = mac.model.removeChoice(.copyPath, at: 1)
        _ = await (first, second)
        #expect(mac.model.copyPath?.offered.map(\.style) == Array(Config.defaultCopyPathStyles.dropFirst()))
    }

    /// Kills L11: one drag is one move.
    @Test func oneDragOfAQuickActionIsOneMove() async throws {
        let mac = try await started(Self.sample + "\n[services]\nitems = [\"open.terminal\", \"open.editor\", \"reveal\"]\n"); defer { mac.cleanUp() }
        async let move = mac.model.moveChoices(.quickActions, from: IndexSet(integer: 0), to: 2)
        async let again = mac.model.moveChoices(.quickActions, from: IndexSet(integer: 0), to: 2)
        _ = await (move, again)
        #expect(mac.model.quickActions?.rows.map(\.id) == ["open.editor", "open.terminal", "reveal"])
    }

    /// Kills L5 and L13: a change of the lists that cannot wait is said under the panel it was made in.
    @Test func aChangeOfTheListsThatCouldNotWaitSaysSoUnderItsOwnPanel() async throws {
        let mac = try await started(Self.sample, patience: .milliseconds(50)); defer { mac.cleanUp() }
        mac.runner.answerSlowly(.seconds(60))
        let repair = Task { await mac.model.repair() }
        #expect(await mac.eventually { mac.model.isWorking })
        let before = text(mac)
        #expect(await mac.model.addChoice(.copyPath, "parent") == false)
        #expect(mac.model.editRefusal == EditRefusal(notice: .busy, tab: .menu, key: "copy_path.styles") && mac.model.notice == .busy)
        #expect(await mac.model.addChoice(.quickActions, "copy-path.name") == false)
        #expect(mac.model.editRefusal == EditRefusal(notice: .busy, tab: .menu, key: "services.items"))
        #expect(await mac.model.setCopyPathTitle("Paths") == false)
        #expect(mac.model.editRefusal == EditRefusal(notice: .busy, tab: .menu, key: "copy_path.title"))
        #expect(text(mac) == before)
        repair.cancel()
    }

    /// Kills L6, L7, L8, L10, L12 and L14: what the note of each change of the lists says, and that it is said on the Finder menu page.
    @Test func theNotesOfTheListsNameWhatWasDoneOnTheFinderMenuPage() async throws {
        let mac = try await started(Self.sample); defer { mac.cleanUp() }
        let parent = try #require(mac.model.copyPath?.others.first { $0.style == .parent }?.title)
        #expect(await mac.model.addChoice(.copyPath, "parent"))
        #expect(mac.model.configEdit?.message == .appMenuEditedAdded(parent) && mac.model.configEdit?.tab == .menu && mac.model.configEdit?.key == "copy_path.styles")
        let last = try #require(mac.model.copyPath?.offered.last?.title)
        #expect(await mac.model.moveChoices(.copyPath, from: IndexSet(integer: Config.defaultCopyPathStyles.count), to: 0))
        #expect(mac.model.configEdit?.message == .appMenuEditedMoved(last) && mac.model.configEdit?.tab == .menu)
        let first = try #require(mac.model.copyPath?.offered.first?.title)
        #expect(await mac.model.removeChoice(.copyPath, at: 1))
        #expect(mac.model.configEdit?.message == .appMenuEditedRemoved(first) && mac.model.configEdit?.tab == .menu)
        #expect(await mac.model.setCopyPathTitle("Paths"))
        #expect(mac.model.configEdit?.tab == .menu && mac.model.configEdit?.key == "copy_path.title")
        let choice = try #require(mac.model.quickActions?.choices.first { $0.id == "copy-path.name" })
        #expect(await mac.model.addChoice(.quickActions, choice.id))
        #expect(mac.model.configEdit?.message == .appMenuEditedAdded(choice.title) && mac.model.configEdit?.tab == .menu && mac.model.configEdit?.key == "services.items")
    }

    /// Kills S9: Edit Menu ends the note of a change of the menu rows only; the panels under the menu keep theirs, with its Undo.
    @Test func theNoteOfACopyPathOrQuickActionsChangeSurvivesEditMenu() async throws {
        let mac = try await started(Self.sample); defer { mac.cleanUp() }
        mac.model.select(.menu)
        #expect(await mac.model.addChoice(.copyPath, "parent"))
        mac.model.setEditingMenu(true)
        #expect(mac.model.configEdit?.key == "copy_path.styles")
        mac.model.setEditingMenu(false)
        #expect(await mac.model.addChoice(.quickActions, "copy-path.name"))
        mac.model.setEditingMenu(true)
        #expect(mac.model.configEdit?.key == "services.items")
    }

    // MARK: A read that began before an edit

    /// Kills S1, S2, S3, S4 and S8: none of what the editors show is put back by a read that began before the edit.
    @Test func aReadThatBeganBeforeAnEditPutsNoneOfTheEditorsBack() async throws {
        let mac = try await started(Self.sample + "\n[menu]\nitems = [\"open-terminal\", \"open-editor\"]\n"); defer { mac.cleanUp() }
        var stale = try #require(mac.model.snapshot)
        stale.readAt = .now
        try await Task.sleep(for: .milliseconds(5))
        #expect(await mac.model.addChoice(.copyPath, "parent"))
        #expect(await mac.model.addChoice(.quickActions, "copy-path.name"))
        await mac.model.setTerminal("terminal")
        await mac.model.moveMenuRow(1, by: 1)
        // An item of the menu that names nothing: a warning among the config's problems.
        #expect(await mac.model.edit([.insert("agent.nobody", into: "menu.items", at: nil)], deciding: "menu.items", saying: .appEditSaved, on: .menu))
        let fresh = try #require(mac.model.snapshot)
        #expect(!fresh.configProblems.isEmpty)
        mac.model.apply(stale)
        let now = try #require(mac.model.snapshot)
        #expect(now.copyPath == fresh.copyPath, "Copy Path")
        #expect(now.quickActions == fresh.quickActions, "Quick Actions")
        #expect(now.general == fresh.general, "the terminal")
        #expect(now.menuEditor == fresh.menuEditor, "the rows of the menu editor")
        #expect(now.configProblems == fresh.configProblems, "the config's problems")
    }

    /// Kills S6 and S7: which file lists the menu and the agents is not put back either (the notes "this Mac's own file lists …").
    @Test func aReadThatBeganBeforeAnEditDoesNotPutBackWhichFileListsTheMenuAndTheAgents() async throws {
        let mac = try await started(Self.sample); defer { mac.cleanUp() }
        var stale = try #require(mac.model.snapshot)
        stale.readAt = .now
        try await Task.sleep(for: .milliseconds(5))
        #expect(await mac.model.edit([.set("menu.items", .strings(["open-terminal"]))], deciding: "menu.items", target: .local, saying: .appEditSaved, on: .menu))
        #expect(await mac.model.edit([.set("general.agents", .strings(["claude"]))], deciding: "general.agents", target: .local, saying: .appEditSaved, on: .agents))
        #expect(mac.model.menuIsMachineOwn && mac.model.agentsAreMachineOwn)
        mac.model.apply(stale)
        #expect(mac.model.menuIsMachineOwn && mac.model.agentsAreMachineOwn)
    }

    /// Kills S5: a proposal that was applied is not put back by a read that began before (the sidebar would count it as waiting).
    @Test func aReadThatBeganBeforeAProposalWasAppliedDoesNotPutItBack() async throws {
        let mac = try await started(Self.sample); defer { mac.cleanUp() }
        _ = try service(mac).submit([.set("agent.claude.args", .strings(["--verbose"]))], actor: .mcp)
        await mac.model.refresh()
        let id = try #require(mac.model.snapshot?.proposals.first?.id)
        var stale = try #require(mac.model.snapshot)
        stale.readAt = .now
        try await Task.sleep(for: .milliseconds(5))
        await mac.model.approveProposal(id)
        #expect(mac.model.proposalsWaiting == 0 && text(mac).contains("--verbose"))
        mac.model.apply(stale)
        #expect(mac.model.proposalsWaiting == 0)
    }

    // MARK: Undo, refusals and held changes

    /// Kills S11 and S12: an Undo that is refused says so under the editor of the change, not only in the corner.
    @Test func anUndoThatIsRefusedIsSaidUnderTheEditorOfTheChange() async throws {
        let mac = try await started(Self.sample); defer { mac.cleanUp() }
        mac.model.select(.menu)
        #expect(await mac.model.setCopyPathTitle("Paths"))
        _ = try service(mac).apply(.set("copy_path.title", .string("Other")), actor: .cli)
        await mac.model.undoEdit()
        #expect(mac.model.notice?.isProblem == true)
        #expect(mac.model.editRefusal?.tab == .menu && mac.model.editRefusal?.key == "copy_path.title" && mac.model.editRefusal?.notice == mac.model.notice, "\(String(describing: mac.model.editRefusal))")
    }

    /// Kills S13 and S14: a change held for the person's yes is made in the file it was asked for and said on the page it was asked on.
    @Test func aHeldChangeOfAStartOptionInThisMacsFileIsMadeThereAndSaidOnTheAgentsPage() async throws {
        let mac = try await started(Self.sample, local: "[[agent.claude.variant]]\nid = \"a\"\ntitle = \"A\"\narguments = [\"--a\"]\n"); defer { mac.cleanUp() }
        let shared = text(mac)
        #expect(await mac.model.addArgument(.variant(agent: "claude", id: "a"), "--dangerously-skip-permissions") == false)
        let held = try #require(mac.model.pendingLoosening)
        #expect(held.target == .local && held.tab == .agents)
        await mac.model.confirmLoosening()
        #expect(localText(mac).contains("--dangerously-skip-permissions") && text(mac) == shared, "shared: \(text(mac)) local: \(localText(mac))")
        #expect(mac.model.configEdit?.tab == .agents && mac.model.configEdit?.target == .local)
    }

    /// Kills S15: a held change of an agent of one's own goes to the file that makes its table.
    @Test func aHeldChangeOfAnAgentWhoseTableIsInThisMacsFileIsMadeThere() async throws {
        let mac = try await started("[general]\nterminal = \"ghostty\"\nbypass_permissions = true\n",
                                           local: "[general]\nagents = [\"claude\", \"mine\"]\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n"); defer { mac.cleanUp() }
        let shared = text(mac)
        #expect(await mac.model.setAgentBypassArgument("mine", "--yolo") == false)
        #expect(mac.model.pendingLoosening?.anchor == "agent.mine.command")
        await mac.model.confirmLoosening()
        #expect(localText(mac).contains("bypass_permission_arg = \"--yolo\"") && text(mac) == shared, "shared: \(text(mac)) local: \(localText(mac))")
    }

    /// Kills S18: the note of a change shows the warnings the change left.
    @Test func theNoteOfAChangeShowsTheWarningsItLeft() async throws {
        let mac = try await started(Self.sample + "\n[menu]\nitems = [\"open-terminal\"]\n"); defer { mac.cleanUp() }
        #expect(await mac.model.edit([.insert("agent.nobody", into: "menu.items", at: nil)], deciding: "menu.items", saying: .appEditSaved, on: .menu))
        #expect(mac.model.configEdit?.warnings.isEmpty == false, "\(String(describing: mac.model.configEdit))")
    }

    /// Kills S21: a refusal goes with the section it was said in.
    @Test func leavingASectionTakesItsRefusalAway() async throws {
        let mac = try await started(Self.sample); defer { mac.cleanUp() }
        mac.model.select(.menu)
        #expect(await mac.model.setCopyPathTitle("two\nlines") == false && mac.model.editRefusal != nil)
        mac.model.select(.agents)
        mac.model.select(.menu)
        #expect(mac.model.editRefusal == nil)
    }

    // MARK: The apps (stage 9)

    /// Kills A2, A4 and A8: an app of this Mac's own file is taken out of that file, and the notes name the app as it is called.
    @Test func anAppOfThisMacsFileIsTakenOutOfThatFileAndTheNotesNameIt() async throws {
        let mac = try await started(Self.sample, local: "[[app]]\nid = \"nova\"\nname = \"Nova Editor\"\nbundle_id = \"com.example.NovaEditor\"\nrole = \"editor\"\n"); defer { mac.cleanUp() }
        let shared = text(mac)
        await mac.model.removeApp("nova")
        #expect(mac.model.app("nova") == nil && !localText(mac).contains("nova") && text(mac) == shared, "\(String(describing: mac.model.editRefusal))")
        #expect(mac.model.configEdit?.message == .appMenuEditedRemoved("Nova Editor"))
        #expect(await mac.model.createApp(name: "  Pulsar  ", bundleID: "dev.pulsar-edit.pulsar", role: .editor) == "pulsar")
        #expect(mac.model.configEdit?.message == .appMenuEditedAdded("Pulsar"))
    }

    // MARK: A gap: what the files hold is asked before the wait

    private static let withEntries = sample + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n\n[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \"t\"\n"

    /// Kills R1.
    @Test func aNewPresetIsMadeWhenAFieldsChangeStartsWithIt() async throws {
        let mac = try await started(Self.withEntries); defer { mac.cleanUp() }
        async let made = mac.model.createPreset(title: "New", prompt: "Read {files}.")
        async let title = mac.model.setPresetTitle("mine", "Mine now")
        let (m, t) = await (made, title)
        #expect(m && t && mac.model.preset("new") != nil, "\(text(mac))")
    }

    /// Kills R2.
    @Test func aNewTemplateIsMadeWhenAFieldsChangeStartsWithIt() async throws {
        let mac = try await started(Self.withEntries); defer { mac.cleanUp() }
        async let made = mac.model.createTemplate(title: "New", fileExtension: "new")
        async let title = mac.model.setTemplateTitle("t", "Tee")
        let (m, t) = await (made, title)
        #expect(m && t && mac.model.template("new") != nil, "\(text(mac))")
    }

    /// Kills R3.
    @Test func aNewStartOptionIsMadeWhenAFieldsChangeStartsWithIt() async throws {
        let mac = try await started(Self.withEntries); defer { mac.cleanUp() }
        async let made = mac.model.createVariant(agent: "claude", title: "New")
        async let command = mac.model.setAgentCommand("claude", "claude-beta")
        let (m, c) = await (made, command)
        #expect(m != nil && c, "\(text(mac))")
    }

    /// Kills R4.
    @Test func aNewAgentIsMadeWhenAFieldsChangeStartsWithIt() async throws {
        let mac = try await started(Self.withEntries); defer { mac.cleanUp() }
        async let made = mac.model.createAgent(name: "Another", command: "another")
        async let command = mac.model.setAgentCommand("claude", "claude-beta")
        let (m, c) = await (made, command)
        #expect(m && c, "\(text(mac))")
    }

    /// Kills A10.
    @Test func aNewAppIsMadeWhenAFieldsChangeStartsWithIt() async throws {
        let mac = try await started(Self.withEntries); defer { mac.cleanUp() }
        async let made = mac.model.createApp(name: "Pulsar", bundleID: "dev.pulsar-edit.pulsar", role: .editor)
        async let title = mac.model.setPresetTitle("mine", "Mine now")
        let (m, t) = await (made, title)
        #expect(m == "pulsar" && t, "\(text(mac))")
    }
}

// MARK: What a review of the window found in the answers to a held change, the stale reads and the apps

@Suite("The setup window's model: what review 26 found")
@MainActor
struct SetupModelReview26Tests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"
    private func text(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.configFile, encoding: .utf8)) ?? "" }
    private func localText(_ mac: Mac) -> String { (try? String(contentsOf: mac.paths.localConfigFile, encoding: .utf8)) ?? "" }
    private func service(_ mac: Mac) -> ConfigService { ConfigService(paths: mac.paths, environment: [:]) }

    private func started(_ config: String = SetupModelReview26Tests.sample, local: String? = nil, patience: Duration? = nil) async throws -> Mac {
        let mac = try Mac(patience: patience)
        try mac.writeConfig(config)
        if let local { try local.write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8) }
        await mac.model.refresh()
        return mac
    }

    private func bundle(_ mac: Mac, name: String, info: [String: Any]) throws -> URL {
        let app = mac.home.appendingPathComponent("\(name).app", isDirectory: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    // MARK: The answer to a held change reaches the field that raised it

    /// The field at the end of a list of arguments always shows "": the config never says what was typed there, so it took no part in a yes (`FieldDraft.answered`).
    @Test func theFieldAtTheEndOfAListOfArgumentsDoesNotAddAHeldArgumentAgainAfterTheYes() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        var field = FieldDraft()
        field.appear(saved: "")
        field.draft = "--dangerously-skip-permissions"
        let begun_first = field.beginCommit()
        let first = try #require(begun_first)
        let done = await mac.model.addArgument(.agent("claude"), first.typed)
        // EditableText asks whether a question is up right after a change that was not made.
        field.endCommit(typed: first.typed, done: done, held: !done && mac.model.pendingLoosening != nil, now: "")
        #expect(!done && mac.model.pendingLoosening != nil && field.held)
        let token = mac.model.fieldAnswerToken
        await mac.model.confirmLoosening()
        #expect(mac.model.agentOptions("claude")?.args == ["--dangerously-skip-permissions"] && mac.model.fieldAnswerToken == token + 1)
        // The window tells the fields (`.onChange(of: answerToken)`); the field shows what the add line shows, which is nothing.
        field.answered(now: "")
        #expect(field.draft == "" && field.beginCommit() == nil, "leaving the field, or the page, adds nothing")
        #expect(mac.model.agentOptions("claude")?.args == ["--dangerously-skip-permissions"])
    }

    @Test func aNoToAQuestionDoesNotTakeTheTextOfAFieldThatWasRefusedAndOnlyTheOneThatAskedGivesItsTextUp() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        // A field whose change was refused keeps what was typed, for the person to put right.
        var refused = FieldDraft()
        refused.appear(saved: "")
        refused.draft = "--dir C:\\x"
        let begun_change = refused.beginCommit()
        let change = try #require(begun_change)
        let done = await mac.model.addArgument(.agent("claude"), change.typed)
        refused.endCommit(typed: change.typed, done: done, held: !done && mac.model.pendingLoosening != nil, now: "")
        #expect(!done && mac.model.editRefusal != nil && !refused.held && refused.draft == "--dir C:\\x")
        // The person is asked something else on the same page and says no.
        var asked = FieldDraft()
        asked.appear(saved: "claude")
        asked.draft = "claude --dangerously-skip-permissions"
        let begun_ask = asked.beginCommit()
        let ask = try #require(begun_ask)
        let askedDone = await mac.model.setAgentCommand("claude", ask.typed)
        asked.endCommit(typed: ask.typed, done: askedDone, held: !askedDone && mac.model.pendingLoosening != nil, now: "claude")
        #expect(!askedDone && mac.model.pendingLoosening != nil && asked.held)
        mac.model.declineLoosening()
        refused.answered(now: "")
        asked.answered(now: mac.model.agentOptions("claude")?.command ?? "")
        #expect(refused.draft == "--dir C:\\x", "what the person was putting right is still there")
        #expect(asked.draft == "claude" && asked.baseline == "claude", "the field that asked shows the file")
    }

    // MARK: A block of text that rests while the window is busy

    @Test func aBlockThatRestsWhileTheWindowIsBusyIsWrittenWhenThePageIsLeftAsWell() async throws {
        let mac = try await started(Self.sample + "\n[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \"t\"\n"); defer { mac.cleanUp() }
        mac.runner.answerSlowly(.milliseconds(150))
        let repair = Task { await mac.model.repair() }
        #expect(await mac.eventually { mac.model.isWorking })
        var field = FieldDraft()
        field.appear(saved: "")
        field.draft = "hello"
        // Five seconds after the last key: the rest asks for the change, which waits for the window.
        let begun_rest = field.beginCommit()
        let rest = try #require(begun_rest)
        let resting = Task { await mac.model.setTemplateContents("t", rest.typed, announcing: false) }
        try await Task.sleep(for: .milliseconds(50))
        // The page is left (`EditableText.onDisappear`): a rest that is writing is let alone (it would stop waiting and say nothing), and the field asks for no second change.
        if !field.committing { resting.cancel() }
        #expect(field.beginCommit() == nil)
        let done = await resting.value
        field.endCommit(typed: rest.typed, done: done, now: mac.model.template("t")?.contents ?? "")
        #expect(done && mac.model.template("t")?.contents == "hello", "what was typed is written once the window is free")
        await repair.value
    }

    // MARK: Reads that began before a change

    @Test func aReadThatBeganBeforeAChangeOfTheQuickActionsDoesNotPutTheOldCheckBack() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        await mac.model.repair()
        #expect(mac.model.check(.services)?.status == .ok)
        var stale = try #require(mac.model.snapshot)
        stale.readAt = .now
        // What a read that began before the change found: the Quick Actions as they were, which differ from the list the change made.
        stale.checks = stale.checks.replacing(DoctorCheck(.services, status: .warn, detail: .doctorServicesDiffer("6", "1", "0"), fix: .doctorFixRunSetup))
        try await Task.sleep(for: .milliseconds(5))
        #expect(await mac.model.addChoice(.quickActions, "copy-path.name"))
        #expect(mac.model.check(.services)?.status == .ok, "the change wrote them again")
        mac.model.apply(stale)
        #expect(mac.model.check(.services)?.status == .ok, "an older read does not know of the change")
    }

    @Test func aProposalThatWasDismissedIsNotPutBackInTheCountByAReadThatBeganBeforeIt() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        _ = try service(mac).submit([.set("agent.claude.args", .strings(["--verbose"]))], actor: .mcp)
        await mac.model.refresh()
        let id = try #require(mac.model.snapshot?.proposals.first?.id)
        mac.model.select(.config)
        _ = await mac.eventually { mac.model.configPage != nil }
        var stale = try #require(mac.model.snapshot)
        stale.readAt = .now
        try await Task.sleep(for: .milliseconds(5))
        await mac.model.dismissProposal(id)
        #expect(mac.model.proposalsWaiting == 0)
        mac.model.select(.agents)
        mac.model.apply(stale)
        #expect(mac.model.proposalsWaiting == 0, "the sidebar counts a proposal that was dismissed")
    }

    // MARK: The apps

    @Test func anAppThatSaysItIsAShellIsMadeATerminalWhateverTheFormAsksFor() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        let app = try bundle(mac, name: "Tabby", info: ["CFBundleName": "Tabby", "CFBundleIdentifier": "org.tabby",
                                                         "CFBundleDocumentTypes": [["CFBundleTypeRole": "Shell", "LSItemContentTypes": ["public.unix-executable"]]]])
        let picked = try #require(mac.model.pickedApp(at: app))
        #expect(picked.runsShellScripts)
        let id = try #require(await mac.model.createApp(name: picked.name, bundleID: picked.bundleID, role: .editor, runsShellScripts: picked.runsShellScripts))
        #expect(mac.model.app(id)?.role == .terminal, "an editor is handed the selected files, and a terminal that is handed one runs it")
        let other = try #require(await mac.model.createApp(name: "Notes", bundleID: "org.notes", role: .editor))
        #expect(mac.model.app(other)?.role == .editor, "an app that does not say so is made what was asked for")
    }

    @Test func theRefusalOfAddAppIsNotCarriedToThePageOfAnApp() async throws {
        let mac = try await started(Self.sample + "\n[[app]]\nid = \"pulsar\"\nname = \"Pulsar\"\nbundle_id = \"dev.pulsar-edit.pulsar\"\nrole = \"editor\"\n"); defer { mac.cleanUp() }
        let bare = try bundle(mac, name: "Bare", info: ["CFBundleName": "Bare"])
        #expect(mac.model.pickedApp(at: bare) == nil && mac.model.editRefusal?.key == "app")
        mac.model.openApp("pulsar")
        #expect(mac.model.editRefusal == nil, "Pulsar's page does not say that “Bare” is not an app Right Here can find")
    }

    /// The window's refusal when an app that this Mac turned off is added after it was picked (the pick said it too, so `pickedApp` hid a missing refusal in `createApp`).
    @Test func addingAnAppThatThisMacTurnedOffAfterItWasPickedSaysWhy() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        try "disabled = [\"terminal\"]\n".write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8)
        await mac.model.refresh()
        #expect(mac.model.editRefusal == nil)
        #expect(await mac.model.createApp(name: "Terminal", bundleID: "com.apple.Terminal", role: .editor) == nil)
        #expect(mac.model.editRefusal == EditRefusal(notice: .appTurnedOff("Terminal"), tab: .overview, key: "app"), "\(String(describing: mac.model.editRefusal))")
    }

    @Test func pickingAnAppLeavesTheRefusalOfAnotherEditor() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        mac.model.refuse(.busy, on: .overview, key: "general.terminal")
        let app = try bundle(mac, name: "Pulsar", info: ["CFBundleName": "Pulsar", "CFBundleIdentifier": "dev.pulsar-edit.pulsar"])
        #expect(mac.model.pickedApp(at: app) != nil)
        #expect(mac.model.editRefusal?.key == "general.terminal")
    }

    // MARK: The first change of the default Quick Actions is a removal or a move

    @Test func theFirstRemovalOfTheDefaultQuickActionsGoesToThisMacsFileWhenThisMacsDefaultIsNotTheOthers() async throws {
        let shared = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\", \"codex\"]\n"
        let mac = try await started(shared, local: "disabled = [\"claude\"]\n"); defer { mac.cleanUp() }
        #expect(mac.model.quickActions?.list.firstChangeTarget == .local)
        #expect(await mac.model.removeChoice(.quickActions, at: 1))
        #expect(text(mac) == shared, "the shared file took this Mac's list, and every other Mac loses an action: \(text(mac))")
        #expect(localText(mac).contains("services"))
    }

    @Test func theFirstMoveOfTheDefaultQuickActionsGoesToThisMacsFileToo() async throws {
        let shared = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\", \"codex\"]\n"
        let mac = try await started(shared, local: "disabled = [\"claude\"]\n"); defer { mac.cleanUp() }
        #expect(await mac.model.moveChoice(.quickActions, 2, by: -1))
        #expect(text(mac) == shared, "the shared file took this Mac's list: \(text(mac))")
        #expect(localText(mac).contains("services"))
    }
}

@Suite("The setup window's model: the page of one thing, which the header names and the section shows")
@MainActor
struct SetupModelDetailHeaderTests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"
        + "\n[[agent.claude.variant]]\nid = \"use-opus\"\ntitle = \"Use Opus\"\narguments = [\"--model\", \"opus\"]\n"
        + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n"
        + "\n[[app]]\nid = \"pulsar\"\nname = \"Pulsar\"\nbundle_id = \"dev.pulsar-edit.pulsar\"\nrole = \"editor\"\n"

    private func started() async throws -> Mac {
        let mac = try Mac()
        try mac.writeConfig(Self.sample)
        await mac.model.refresh()
        return mac
    }

    @Test func eachPageOfOneThingIsNamedWithThePageItsBackButtonReturnsTo() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        let model = mac.model, l10n = mac.model.localizer
        model.select(.agents)
        #expect(model.openDetailPage == nil && model.detailHeader(l10n) == nil, "the section's own page has no back button")

        model.openAgentOptions("claude")
        let agent = try #require(model.agentOptions("claude")?.name)
        #expect(model.openDetailPage == .agent("claude"))
        #expect(model.detailHeader(l10n)?.title == agent && model.detailHeader(l10n)?.parent == l10n.string(.appTabAgents))

        model.openVariant(VariantRef(agent: "claude", id: "use-opus"))
        #expect(model.openDetailPage == .variant(VariantRef(agent: "claude", id: "use-opus")), "a start option's page is in front of its agent's")
        #expect(model.detailHeader(l10n)?.title == "Use Opus" && model.detailHeader(l10n)?.parent == agent)
        model.closeDetail()
        #expect(model.openDetailPage == .agent("claude"), "back from a start option is its agent's page, not the list")
        model.closeDetail()
        #expect(model.openDetailPage == nil)

        model.openPreset("mine")
        #expect(model.openDetailPage == .preset("mine") && model.detailHeader(l10n)?.title == "Mine" && model.detailHeader(l10n)?.parent == l10n.string(.appTabAgents))
        model.closeDetail()
        #expect(model.openDetailPage == nil && model.presetDetail == nil)

        model.select(.menu)
        await model.customizeTemplates()
        model.openTemplate("txt")
        #expect(model.openDetailPage == .template("txt") && model.detailHeader(l10n)?.parent == l10n.string(.appMenuTitle))
        model.closeDetail()
        #expect(model.templateDetail == nil)

        model.select(.overview)
        model.openApp("pulsar")
        #expect(model.openDetailPage == .app("pulsar") && model.detailHeader(l10n)?.title == "Pulsar" && model.detailHeader(l10n)?.parent == l10n.string(.appTabOverview))
        model.closeDetail()
        #expect(model.appDetail == nil && model.openDetailPage == nil)
    }

    @Test func aPageOfAThingThatIsNotThereIsNoPage() async throws {
        let mac = try await started(); defer { mac.cleanUp() }
        mac.model.select(.agents)
        mac.model.openAgentOptions("nobody")
        #expect(mac.model.openDetailPage == nil && mac.model.detailHeader(mac.model.localizer) == nil, "the header names no page that the section does not show")
        mac.model.openVariant(VariantRef(agent: "claude", id: "gone"))
        #expect(mac.model.openDetailPage == nil)
    }

    @Test func theWindowsButtonsStandOverTheHeaderWhenTheWindowRunsTheOtherWayFromTheMac() {
        #expect(!SetupModel.windowButtonsOverHeader(titlebarRightToLeft: false, windowRightToLeft: false))
        #expect(!SetupModel.windowButtonsOverHeader(titlebarRightToLeft: true, windowRightToLeft: true), "Arabic on an Arabic Mac: the buttons are over the sidebar")
        #expect(SetupModel.windowButtonsOverHeader(titlebarRightToLeft: false, windowRightToLeft: true), "Arabic on an English Mac")
        #expect(SetupModel.windowButtonsOverHeader(titlebarRightToLeft: true, windowRightToLeft: false), "English on a Hebrew Mac")
    }

    @Test func theHeaderAndThePageStandInTheMiddleOfAWideWindowByOneInset() {
        #expect(SetupModel.pageInset(columnWidth: 628, widestPage: 780) == 0, "a window of its default width: the page fills the space")
        #expect(SetupModel.pageInset(columnWidth: 1168, widestPage: 780) == 194, "a window 1400 points wide")
        // The scroll view's own width is not what places the page: with a scroll bar of 17 points it would be 8.5 points off the header.
        #expect(SetupModel.pageInset(columnWidth: 1168 - 17, widestPage: 780) != SetupModel.pageInset(columnWidth: 1168, widestPage: 780))
    }

    @Test func theHeaderLeavesTheWindowsButtonsRoomOnlyWhereTheyStandOverIt() {
        #expect(SetupModel.headerRoomForWindowButtons(over: false, columnWidth: 568, widestHeader: 780) == 0)
        #expect(SetupModel.headerRoomForWindowButtons(over: true, columnWidth: 568, widestHeader: 780) == 56, "the narrowest window")
        #expect(SetupModel.headerRoomForWindowButtons(over: true, columnWidth: 628, widestHeader: 780) == 56, "a window of its default width")
        #expect(SetupModel.headerRoomForWindowButtons(over: true, columnWidth: 800, widestHeader: 780) == 46, "the header begins to move away from the edge")
        #expect(SetupModel.headerRoomForWindowButtons(over: true, columnWidth: 1168, widestHeader: 780) == 0, "a wide window: the header is far from the buttons")
    }
}

@Suite("The setup window's model: icons are read before a page draws them")
struct SetupModelIconWarmingTests {
    @Test func theFirstRunsAppsAreWarmedWithTheRest() {
        let offer = SetupOffer(terminals: [.init(id: "ghostty", name: "Ghostty", available: true, icon: .app("com.mitchellh.ghostty"))],
                               editors: [.init(id: "vscode", name: "Visual Studio Code", available: true, icon: .app("com.microsoft.VSCode"))],
                               agents: [.init(id: "claude", name: "Claude Code", available: true)])
        let wanted = SetupModel.iconsToWarm([], offer: offer)
        #expect(wanted == [.app("com.mitchellh.ghostty"), .app("com.microsoft.VSCode")], "the chips of a first run draw these; an agent has no icon")
        #expect(SetupModel.iconsToWarm([]) == [])
    }

    @Test func aNewFilesLineInTheListsHasTheNewFileGlyphAndAnAppKeepsItsIcon() {
        #expect(SetupModel.listIcon(.fileType("md")) == .symbol("doc.badge.plus"), "the file type's own icon, a white page, drew as a faint sliver among glyphs")
        #expect(SetupModel.listIcon(.app("com.mitchellh.ghostty")) == .app("com.mitchellh.ghostty"))
        #expect(SetupModel.listIcon(.symbol("terminal")) == .symbol("terminal"))
        #expect(SetupModel.listIcon(nil) == nil)
    }
}
