import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

/// Answers every process with success and notes, at each call, whether the probe says it is between switching the extension off and on.
private final class ObservingRunner: ProcessRunner, @unchecked Sendable {
    private let activity: ProbeActivity
    private let lock = NSLock()
    private var seen: [(arguments: [String], switching: Bool)] = []

    init(activity: ProbeActivity) { self.activity = activity }

    var calls: [(arguments: [String], switching: Bool)] { lock.withLock { seen } }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        lock.withLock { seen.append((step.arguments, activity.isSwitching)) }
        return ProcessResult(status: 0)
    }
}

/// A process that was stopped for running past its limit.
private struct StuckRunner: ProcessRunner {
    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        ProcessResult(status: 15, terminatedAfter: timeout ?? .seconds(1))
    }
}

@Suite("ExtensionProbe")
struct ExtensionProbeTests {
    private func automationResults(in log: URL, since start: Date) -> [AutomationProbe.Result]? {
        ExtensionProbe.latestReport(.automation, in: log, since: start).flatMap { try? JSONDecoder().decode([AutomationProbe.Result].self, from: $0) }
    }

    @Test func readsTheNewestProbeLineAfterTheStart() throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("rh-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: log) }
        let start = ISO8601DateFormatter().date(from: "2026-10-12T00:42:00Z")!
        try """
        2026-10-12T00:10:00Z open.app.zed: Zed is not installed.
        2026-10-12T00:39:55Z probe automation: [{"application":"Ghostty","bundleID":"a","outcome":"denied"}]
        2026-10-12T00:42:17Z probe automation: [{"application":"Ghostty","bundleID":"com.mitchellh.ghostty","outcome":"granted"}]
        2026-10-12T00:42:18Z ok run something
        """.write(to: log, atomically: true, encoding: .utf8)
        let results = try #require(automationResults(in: log, since: start))
        #expect(results.map(\.outcome) == [.granted])
    }

    @Test func ignoresProbeLinesFromBeforeTheStart() throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("rh-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: log) }
        try #"2026-10-12T00:39:55Z probe automation: [{"application":"Ghostty","bundleID":"a","outcome":"granted"}]"#.write(to: log, atomically: true, encoding: .utf8)
        let start = ISO8601DateFormatter().date(from: "2026-10-12T00:42:00Z")!
        #expect(automationResults(in: log, since: start) == nil)
    }

    @Test func eachKindOfProbeReadsOnlyItsOwnLines() throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("rh-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: log) }
        let start = ISO8601DateFormatter().date(from: "2026-10-12T00:42:00Z")!
        try """
        2026-10-12T00:42:17Z probe automation: [{"application":"Ghostty","bundleID":"a","outcome":"granted"}]
        2026-10-12T00:42:30Z probe launch: {"application":"Ghostty","outcome":"ran","seconds":1.2,"shell":"/bin/zsh"}
        """.write(to: log, atomically: true, encoding: .utf8)
        let launch = try #require(ExtensionProbe.latestReport(.launch, in: log, since: start))
        let decoded = try JSONDecoder().decode(LaunchProbe.Result.self, from: launch)
        #expect(decoded.outcome == .ran)
        #expect(decoded.shell == "/bin/zsh")
        #expect(automationResults(in: log, since: start)?.map(\.outcome) == [.granted])
    }

    @Test func theMarkerNamesAPlacementOnlyFromAFixedVocabulary() {
        #expect(ExtensionProbe.markerText(placement: nil) == "launch")
        #expect(ExtensionProbe.markerText(placement: .newTab) == "launch:tab")
        #expect(ExtensionProbe.markerText(placement: .newWindow) == "launch:window")
    }

    @Test func aMissingLogMeansNoResult() {
        #expect(automationResults(in: URL(fileURLWithPath: "/nonexistent/rh.log"), since: Date()) == nil)
    }

    // MARK: The probe's guards (the app waits for the switch, a stuck daemon, a test without a trial home)

    /// The probe restarts the extension by switching it off and on. A process that ends between the two (the setup window is closed, which quits the app)
    /// leaves Finder without its menu, so the app asks `ProbeActivity` before it quits.
    @Test func theAppIsToldNotToQuitBetweenSwitchingTheExtensionOffAndOn() async throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let activity = ProbeActivity()
        let runner = ObservingRunner(activity: activity)
        let probe = ExtensionProbe(paths: RHPaths(environment: [:], home: home), facts: FakeSystemFacts(homeDirectory: home), runner: runner, activity: activity)
        _ = await probe.runLaunch(timeout: .milliseconds(50))
        let calls = runner.calls
        #expect(calls.map { $0.arguments.prefix(2).joined(separator: " ") } == ["-e ignore", "-e use"])
        #expect(calls.allSatisfy { $0.switching }, "the app must not quit while the extension is off")
        #expect(!activity.isSwitching, "and may quit as soon as it is on again")
    }

    @Test func aProcessATestStartedWithoutATrialHomeDoesNotRestartTheExtension() async throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let runner = FakeProcessRunner()
        let probe = ExtensionProbe(paths: RHPaths(environment: [:], home: home), facts: FakeSystemFacts(homeDirectory: home), runner: runner, activity: ProbeActivity(),
                                   environment: ["RH_NO_UI": "1"])
        #expect(await probe.runLaunch(timeout: .milliseconds(50)) == nil)
        #expect(runner.recorded.isEmpty, "pluginkit was started: \(runner.recorded)")
        #expect(!FileManager.default.fileExists(atPath: ProbeMarker.url(in: RHPaths(environment: [:], home: home)).path), "and no request was left for the extension")
    }

    @Test func aLookAtTheRegistrationThatNeverComesBackIsUnknownAndNotMissing() async {
        let status = await FinderExtensionManager(runner: StuckRunner()).status()
        #expect(status.state == .unanswered && status.paths.isEmpty)
        let check = await Doctor.extensionCheck(runner: StuckRunner())
        #expect(check.status == .warn, "a failure would be a first run for the window, and the extension may be fine")
        #expect(check.detail?.english().contains("did not answer within 20 seconds") == true)
    }

    @Test func aPluginkitCallThatNeverComesBackIsStoppedAndSaysSo() async {
        let manager = FinderExtensionManager(runner: StuckRunner())
        await #expect(throws: ExecutionError.timedOut(step: "pluginkit -a /Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex", seconds: 30)) {
            try await manager.register(appexPath: "/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex")
        }
    }
}

@Suite("AutomationProbe")
struct AutomationProbeTests {
    private let facts = FakeSystemFacts(runningApplications: ["com.mitchellh.ghostty"])

    @Test func anAppThatIsNotRunningIsNotStarted() async {
        let runner = FakeProcessRunner()
        let result = await AutomationProbe(facts: FakeSystemFacts(), runner: runner).check(name: "Ghostty", bundleID: "com.mitchellh.ghostty")
        #expect(result.outcome == .notRunning)
        #expect(runner.recorded.isEmpty)
    }

    @Test func successMeansGranted() async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "Ghostty\n")])
        let result = await AutomationProbe(facts: facts, runner: runner).check(name: "Ghostty", bundleID: "com.mitchellh.ghostty")
        #expect(result.outcome == .granted)
        #expect(runner.recorded.first?.arguments == ["-", "com.mitchellh.ghostty"])
        #expect(runner.recorded.first?.standardInput?.contains("get name") == true)
    }

    @Test("osascript error codes map to outcomes", arguments: [
        ("execution error: Not authorized to send Apple events to Ghostty. (-1743)", AutomationProbe.Outcome.denied),
        ("execution error: Ghostty got an error: AppleEvent timed out. (-1712)", .timedOut),
        ("execution error: something else (-50)", .failed)
    ])
    func outcomes(error: String, expected: AutomationProbe.Outcome) async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 1, standardError: error)])
        let result = await AutomationProbe(facts: facts, runner: runner).check(name: "Ghostty", bundleID: "com.mitchellh.ghostty")
        #expect(result.outcome == expected)
    }

    @Test func aProbeTheWatchdogHadToStopIsATimeOutWhateverItPrinted() async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 15, terminatedAfter: .seconds(40))])
        let result = await AutomationProbe(facts: facts, runner: runner).check(name: "Ghostty", bundleID: "com.mitchellh.ghostty")
        #expect(result.outcome == .timedOut)
    }
}
