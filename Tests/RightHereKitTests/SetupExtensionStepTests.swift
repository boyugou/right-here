import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

// What the report says about the Finder extension step (found by the independent review of the app). A temporary home, fake system facts, a
// scripted process runner: nothing real is started.

/// Answers each process by what it is, so a test does not depend on the order of the calls.
private final class ExtensionStepRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [ProcessStep] = []
    private let answer: @Sendable (ProcessStep) -> ProcessResult

    init(_ answer: @escaping @Sendable (ProcessStep) -> ProcessResult) { self.answer = answer }

    var recorded: [ProcessStep] { lock.withLock { calls } }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        lock.withLock { calls.append(step) }
        return answer(step)
    }
}

@Suite("The Finder extension step of a setup")
struct SetupExtensionStepTests {
    /// `pluginkit -r` can fail (it says so on standard error and exits 1); the setup ignores that (`try?`) and then writes "removed the
    /// stale registration of …" into the step. The window (and `rh setup`, and the JSON an AI agent reads) says something that did not happen,
    /// and the doctor still warns about the second location a moment later.
    @Test func aStaleRegistrationThatCouldNotBeRemovedIsNotReportedAsRemoved() async throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Applications/Right Here.app")
        let appex = HostApp.extensionURL(in: app).path
        try FileManager.default.createDirectory(atPath: appex, withIntermediateDirectories: true)
        let stale = "/Users/tester/DerivedData/Build/Products/Release/Right Here.app/Contents/PlugIns/FinderExtension.appex"
        let listed = """
        +    \(AppIdentity.extensionBundleID)(0.3.0)\tAAAA\t2026-10-16 07:33:49 +0000\t\(appex)
             \(AppIdentity.extensionBundleID)(0.2.0)\tBBBB\t2026-10-12 07:33:49 +0000\t\(stale)

        """
        let runner = ExtensionStepRunner { step in
            if step.arguments.first == "-m" { return ProcessResult(status: 0, standardOutput: listed) }
            if step.arguments.first == "-r" { return ProcessResult(status: 1, standardError: "pluginkit: could not remove \(stale)") }
            return ProcessResult(status: 0)
        }
        let facts = FakeSystemFacts(homeDirectory: home, directories: [home.path])
        let setup = SetupRunner(facts: facts, paths: RHPaths(environment: [:], home: home), runner: runner, rhPath: app.appendingPathComponent("Contents/Helpers/rh").path,
                                app: app, trialHome: nil, settle: .zero)
        let report = try await setup.run(SetupRequest(pieces: [.finderExtension]))

        #expect(runner.recorded.contains { $0.arguments.first == "-r" }, "it did try to remove the stale copy")
        let step = try #require(report.step(.finderExtension))
        let text = step.english()
        #expect(!text.contains("removed the stale registration"), "pluginkit -r failed, and the step says: \(text)")
    }
}
