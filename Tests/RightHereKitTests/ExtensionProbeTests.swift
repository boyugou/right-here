import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("ExtensionProbe")
struct ExtensionProbeTests {
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
        let results = try #require(ExtensionProbe.latestResults(in: log, since: start))
        #expect(results.map(\.outcome) == [.granted])
    }

    @Test func ignoresProbeLinesFromBeforeTheStart() throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("rh-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: log) }
        try #"2026-10-12T00:39:55Z probe automation: [{"application":"Ghostty","bundleID":"a","outcome":"granted"}]"#.write(to: log, atomically: true, encoding: .utf8)
        let start = ISO8601DateFormatter().date(from: "2026-10-12T00:42:00Z")!
        #expect(ExtensionProbe.latestResults(in: log, since: start) == nil)
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
        #expect(ExtensionProbe.latestResults(in: log, since: start)?.map(\.outcome) == [.granted])
    }

    @Test func theMarkerNamesAPlacementOnlyFromAFixedVocabulary() {
        #expect(ExtensionProbe.markerText(placement: nil) == "launch")
        #expect(ExtensionProbe.markerText(placement: .newTab) == "launch:tab")
        #expect(ExtensionProbe.markerText(placement: .newWindow) == "launch:window")
    }

    @Test func aMissingLogMeansNoResult() {
        #expect(ExtensionProbe.latestResults(in: URL(fileURLWithPath: "/nonexistent/rh.log"), since: Date()) == nil)
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
}
