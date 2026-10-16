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

@Suite("The Finder extension launch probe")
struct ExtensionProbeTests {
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

    @Test func aPluginkitCallThatNeverComesBackIsStoppedAndSaysSo() async {
        let manager = FinderExtensionManager(runner: StuckRunner())
        await #expect(throws: ExecutionError.timedOut(step: "pluginkit -a /Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex", seconds: 30)) {
            try await manager.register(appexPath: "/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex")
        }
    }
}
