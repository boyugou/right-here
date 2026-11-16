import Foundation
import Synchronization
import Testing
import RightHereCore
import RightHereKit
@testable import AppModel

/// Answers the questions the window asks of the Mac as a scripted Mac would: pluginkit says whether the Finder extension is switched on, the login shell finds no agent
/// command, everything else succeeds with nothing to say. It notes what it was asked.
final class ScriptedMac: ProcessRunner, Sendable {
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
struct Mac {
    let home: URL
    let paths: RHPaths
    let runner = ScriptedMac()
    let model: SetupModel
    private let visible: Switch

    static let inTheApplicationsFolder = "/Applications/Right Here.app/Contents/Helpers/rh"

    init(helper: String = Mac.inTheApplicationsFolder, visible: Bool = true, pollInterval: Duration = .milliseconds(10), idleInterval: Duration = .milliseconds(10),
         activationQuietPeriod: Duration = .zero, readFolders: (@Sendable () async -> FolderSnapshot)? = nil,
         pickFolder: @escaping @MainActor (SetupModel.FolderChoice) async -> URL? = { _ in nil },
         worktreeRunner: (any ProcessRunner)? = nil, gitRoots: [String] = [],
         loaderRunner: (any ProcessRunner)? = nil, afterConfigRead: (@Sendable () async -> Void)? = nil,
         writeClipboard: @escaping @MainActor (String) -> Void = { _ in }) throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
        let facts = FakeSystemFacts(homeDirectory: home, directories: [home.path], gitRoots: gitRoots, applications: [
            "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
            "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        ])
        let flag = Switch(visible)
        self.visible = flag
        let loader = SetupLoader(facts: facts, paths: paths, runner: loaderRunner ?? runner, helperPath: helper, localizer: .english)
        let configRead: (@Sendable () async -> SetupConfigState)?
        if let afterConfigRead {
            configRead = {
                let state = await loader.configState()
                await afterConfigRead()
                return state
            }
        } else {
            configRead = nil
        }
        model = SetupModel(
            loader: loader,
            actions: SetupActions(facts: facts, paths: paths, runner: runner, helperPath: helper, app: nil, trialHome: home),
            facts: facts, helper: helper, pollInterval: pollInterval, idleInterval: idleInterval,
            activationQuietPeriod: activationQuietPeriod, windowIsVisible: { flag.isOn }, readFolders: readFolders,
            readConfigState: configRead, pickFolder: pickFolder,
            browser: WorktreeBrowser(runner: worktreeRunner ?? runner), writeClipboard: writeClipboard)
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
