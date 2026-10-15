import Foundation
import Synchronization
import Testing
import RightHereCore
@testable import RightHereKit

/// A throwaway home with a config folder in it. Nothing outside it is touched, and no process is started.
private struct Machine {
    let home: URL
    let paths: RHPaths
    let ghostty = URL(fileURLWithPath: "/Applications/Ghostty.app")
    let vscode = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")

    init() throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }

    var facts: FakeSystemFacts {
        FakeSystemFacts(homeDirectory: home, directories: [home.path],
                        applications: ["com.mitchellh.ghostty": ghostty, "com.microsoft.VSCode": vscode])
    }

    func writeConfig(_ text: String) throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try text.write(to: paths.configFile, atomically: true, encoding: .utf8)
    }

    func loader(runner: any ProcessRunner) -> SetupLoader {
        SetupLoader(facts: facts, paths: paths, runner: runner, helperPath: "/opt/rh/bin/rh", localizer: .english)
    }
}

private let pluginkitEnabled = "+    \(AppIdentity.extensionBundleID)(1.0)\tU1\t2026-10-11 23:29:41 +0000\t/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex\n"

/// Remembers whether each question about the machine was asked on the main thread. The questions the loader asks of the
/// facts are plain calls made in its own body, so they say where the body runs; a process runner would not (an `async`
/// function that is not isolated hops off the main actor by itself).
private final class ThreadProbeFacts: SystemFacts, Sendable {
    private let base: FakeSystemFacts
    private let asked = Mutex<[Bool]>([])

    init(_ base: FakeSystemFacts) { self.base = base }

    var onMainThread: [Bool] { asked.withLock { $0 } }
    private func note() { asked.withLock { $0.append(pthread_main_np() != 0) } }

    var homeDirectory: URL { note(); return base.homeDirectory }
    var currentDirectory: URL { base.currentDirectory }
    var loginShell: String { base.loginShell }
    func isDirectory(_ url: URL) -> Bool? { note(); return base.isDirectory(url) }
    func fileExists(_ url: URL) -> Bool { note(); return base.fileExists(url) }
    func itemState(_ url: URL) -> ItemState { base.itemState(url) }
    func gitRoot(containing url: URL) -> URL? { base.gitRoot(containing: url) }
    func applicationURL(bundleID: String) -> URL? { note(); return base.applicationURL(bundleID: bundleID) }
    func displayName(bundleID: String) -> String? { note(); return base.displayName(bundleID: bundleID) }
    func bundleVersion(bundleID: String) -> String? { base.bundleVersion(bundleID: bundleID) }
    func isRunning(bundleID: String) -> Bool { base.isRunning(bundleID: bundleID) }
    func environment(_ key: String) -> String? { base.environment(key) }
    func onDiskPath(_ url: URL) -> String { base.onDiskPath(url) }
}

@Suite("SetupLoader")
struct SetupLoaderTests {
    @Test func readsTheChecksTheMenuAndTheFoldersInOnePass() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = []\n")
        try StateStore(pins: ["/Users/tester/Projects/app"], recents: ["/Users/tester/Projects/web", "/Users/tester/Notes"]).save(paths: machine.paths)

        let snapshot = await machine.loader(runner: FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: pluginkitEnabled)])).load()

        #expect(snapshot.checks.first?.id == .config)
        #expect(snapshot.checks.first { $0.id == .terminalDefault }?.openedApp == "Ghostty")
        #expect(snapshot.checks.first { $0.id == .finderExtension }?.status == .ok)
        #expect(snapshot.folders.pins == ["/Users/tester/Projects/app"])
        #expect(snapshot.folders.recents == ["/Users/tester/Projects/web", "/Users/tester/Notes"])
        #expect(snapshot.configFile == machine.paths.configFile)
        #expect(snapshot.configProblems.isEmpty)
        #expect(!snapshot.configHasErrors)
        let config = ConfigStore.load(paths: machine.paths)
        #expect(snapshot.menu == MenuPreview.folderMenu(config.result, facts: machine.facts, folder: machine.home, localizer: .english))
        #expect(!snapshot.menu.isEmpty)
    }

    @Test func aMachineWithNothingSetUpStillAnswers() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        let snapshot = await machine.loader(runner: FakeProcessRunner()).load()
        #expect(!snapshot.checks.isEmpty)
        #expect(snapshot.folders.pins.isEmpty && snapshot.folders.recents.isEmpty)
        #expect(snapshot.configProblems.isEmpty)
    }

    @Test func aConfigWithErrorsHasNoMenuAndSaysWhatIsWrong() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general\nterminal = \"ghostty\"\n")
        let snapshot = await machine.loader(runner: FakeProcessRunner()).load()
        #expect(snapshot.menu.isEmpty)
        #expect(snapshot.configHasErrors)
        #expect(snapshot.configProblems.first?.severity == .error)
        #expect(snapshot.configProblems.first?.summary(file: snapshot.configFile).hasPrefix("error: config.toml") == true)
        #expect(snapshot.checks.first { $0.id == .config }?.status == .fail)
    }

    @Test func aWarningIsAProblemButTheMenuIsStillThere() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nterminal = \"ghostty\"\nunknown_setting = 1\n")
        let snapshot = await machine.loader(runner: FakeProcessRunner()).load()
        #expect(snapshot.configProblems.contains { $0.severity == .warning })
        #expect(!snapshot.configHasErrors)
        #expect(!snapshot.menu.isEmpty)
    }

    @Test func theLoginShellIsAskedOncePerLoadAndGitNever() async throws {
        // The window's refresh used to read the config three times and run `git worktree list` as well; the shell is the
        // slow part (it runs the person's startup files), so it may be started once and only for the agents.
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nagents = [\"claude\"]\n")
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "claude\n"), ProcessResult(status: 0, standardOutput: pluginkitEnabled)])
        _ = await machine.loader(runner: runner).load()
        #expect(runner.recorded.map(\.executable) == ["/bin/zsh", "/usr/bin/pluginkit"])
    }

    @Test func noAgentsMeansNoShellAtAll() async throws {
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nagents = []\n")
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: pluginkitEnabled)])
        _ = await machine.loader(runner: runner).load()
        #expect(runner.recorded.map(\.executable) == ["/usr/bin/pluginkit"])
    }

    @MainActor
    @Test func itDoesItsWorkOffTheMainThreadEvenWhenTheCallerIsOnIt() async throws {
        // The doctor starts the login shell and the config and the state are read from disk: a window that did that on its
        // own thread would stop answering while the person's startup files ran.
        #expect(pthread_main_np() != 0)
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n")
        let facts = ThreadProbeFacts(machine.facts)
        let loader = SetupLoader(facts: facts, paths: machine.paths, runner: FakeProcessRunner(), helperPath: nil, localizer: .english)
        _ = await loader.load()
        #expect(!facts.onMainThread.isEmpty)
        #expect(facts.onMainThread.allSatisfy { !$0 })
    }
}

@Suite("Doctor: the launch probe on its own")
struct LaunchProbeAloneTests {
    @Test func itAsksTheExtensionAndNeverTheLoginShell() async throws {
        // After "Test Terminal Launch" the window used to run the whole doctor again with the probe added, which asks the
        // login shell for the agents' commands a second time for a row that is only about the terminal.
        let machine = try Machine(); defer { machine.cleanUp() }
        try machine.writeConfig("[general]\nagents = [\"claude\", \"codex\"]\n")
        try FileManager.default.createDirectory(at: machine.paths.logDirectory, withIntermediateDirectories: true)
        // The probe reads the log for a report newer than its own start; this one is dated ahead of it.
        let when = ISO8601DateFormatter().string(from: Date().addingTimeInterval(30))
        try """
        \(when) probe launch: {"application":"Ghostty","outcome":"ran","seconds":1.2,"accepted":0.4,"shell":"/bin/zsh"}
        """.write(to: machine.paths.logFile, atomically: true, encoding: .utf8)

        let runner = FakeProcessRunner()
        let doctor = Doctor(facts: machine.facts, paths: machine.paths, loaded: ConfigStore.load(paths: machine.paths), runner: runner, rhPath: "/opt/rh/bin/rh")
        let check = await doctor.launchCheck()

        #expect(check.id == .finderLaunch)
        #expect(check.status == .ok)
        #expect(!runner.recorded.contains { $0.executable == "/bin/zsh" })
        #expect(runner.recorded.allSatisfy { $0.executable == "/usr/bin/pluginkit" })
    }
}
