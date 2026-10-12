import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("LiveExecutor")
struct LiveExecutorTests {
    private func executor(_ runner: FakeProcessRunner, _ pasteboard: RecordingPasteboard = RecordingPasteboard()) -> LiveExecutor {
        LiveExecutor(runner: runner, pasteboard: pasteboard)
    }

    @Test func openRunsLaunchServicesWithTheBundleId() async throws {
        let runner = FakeProcessRunner()
        let plan = LaunchPlan(action: "t", summary: "t", steps: [.open(OpenStep(bundleID: "com.apple.Terminal", targets: ["/tmp/a b"]))])
        try await executor(runner).execute(plan)
        #expect(runner.recorded == [ProcessStep(executable: "/usr/bin/open", arguments: ["-b", "com.apple.Terminal", "/tmp/a b"])])
    }

    @Test func openWithoutActivationIsBackgrounded() async throws {
        let runner = FakeProcessRunner()
        let plan = LaunchPlan(action: "t", summary: "t", steps: [.open(OpenStep(bundleID: nil, targets: ["/tmp/x"], activate: false))])
        try await executor(runner).execute(plan)
        #expect(runner.recorded.first?.arguments == ["-g", "/tmp/x"])
    }

    @Test func urlsAndRevealGoThroughOpen() async throws {
        let runner = FakeProcessRunner()
        let plan = LaunchPlan(action: "t", summary: "t", steps: [.openURL("claude-cli://open?cwd=%2Ftmp"), .reveal(["/tmp/a", "/tmp/b"])])
        try await executor(runner).execute(plan)
        #expect(runner.recorded.map(\.arguments) == [["claude-cli://open?cwd=%2Ftmp"], ["-R", "/tmp/a", "/tmp/b"]])
    }

    @Test func appleScriptSourceGoesToStandardInputAndValuesToArguments() async throws {
        let runner = FakeProcessRunner()
        let script = AppleScriptStep(source: "on run argv\nend run", arguments: ["/tmp/it's here", "claude"], controls: "Ghostty")
        try await executor(runner).execute(LaunchPlan(action: "t", summary: "t", steps: [.appleScript(script)]))
        let call = try #require(runner.recorded.first)
        #expect(call.executable == "/usr/bin/osascript")
        #expect(call.arguments == ["-", "/tmp/it's here", "claude"])
        #expect(call.standardInput == "on run argv\nend run")
    }

    @Test func automationDenialIsRecognized() async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 1, standardError: "execution error: Not authorized to send Apple events to Ghostty. (-1743)")])
        let script = AppleScriptStep(source: "x", controls: "Ghostty")
        await #expect(throws: ExecutionError.automationDenied(application: "Ghostty")) {
            try await executor(runner).execute(LaunchPlan(action: "t", summary: "t", steps: [.appleScript(script)]))
        }
    }

    @Test func failureStopsLaterSteps() async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 1, standardError: "boom")])
        let pasteboard = RecordingPasteboard()
        let plan = LaunchPlan(action: "t", summary: "t", steps: [.openURL("x://y"), .copyToPasteboard("never")])
        await #expect(throws: ExecutionError.self) { try await executor(runner, pasteboard).execute(plan) }
        #expect(pasteboard.written.isEmpty)
    }

    @Test func clipboardStep() async throws {
        let pasteboard = RecordingPasteboard()
        try await executor(FakeProcessRunner(), pasteboard).execute(LaunchPlan(action: "t", summary: "t", steps: [.copyToPasteboard("hello\nworld")]))
        #expect(pasteboard.written == ["hello\nworld"])
    }

    @Test func createFileWritesContentsAndNeverOverwrites() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("untitled.md").path
        let plan = LaunchPlan(action: "t", summary: "t", steps: [.createFile(CreateFileStep(path: path, contents: "# Title\n"))])
        try await executor(FakeProcessRunner()).execute(plan)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "# Title\n")

        await #expect(throws: ExecutionError.fileExists(path: path)) { try await executor(FakeProcessRunner()).execute(plan) }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "# Title\n")
    }

    @Test func createFileInAMissingFolderFails() async {
        let plan = LaunchPlan(action: "t", summary: "t", steps: [.createFile(CreateFileStep(path: "/nonexistent-rh-test-folder/x.txt"))])
        await #expect(throws: ExecutionError.self) { try await executor(FakeProcessRunner()).execute(plan) }
    }

    @Test func reportListsEveryStep() async throws {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "hello\n")])
        let plan = LaunchPlan(action: "t", summary: "t", steps: [.run(ProcessStep(executable: "/bin/echo", arguments: ["hello"])), .pause(milliseconds: 1)])
        let report = try await executor(runner).execute(plan)
        #expect(report.steps.map(\.output) == ["hello", nil])
    }
}

@Suite("LiveProcessRunner")
struct LiveProcessRunnerTests {
    @Test func capturesOutputAndStatus() async throws {
        let result = try await LiveProcessRunner().run(ProcessStep(executable: "/bin/sh", arguments: ["-c", "echo out; echo err >&2; exit 3"]))
        #expect(result.status == 3)
        #expect(result.standardOutput == "out\n")
        #expect(result.standardError == "err\n")
    }

    @Test func feedsStandardInput() async throws {
        let result = try await LiveProcessRunner().run(ProcessStep(executable: "/bin/cat", standardInput: "typed text\n"))
        #expect(result.standardOutput == "typed text\n")
    }

    @Test func passesEnvironmentAndDirectory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let step = ProcessStep(executable: "/bin/sh", arguments: ["-c", "printf '%s|%s' \"$RH_TEST\" \"$PWD\""], environment: ["RH_TEST": "yes"], currentDirectory: directory.path)
        let result = try await LiveProcessRunner().run(step)
        #expect(result.standardOutput.hasPrefix("yes|"))
        #expect(result.standardOutput.hasSuffix(directory.lastPathComponent))
    }

    @Test func timeoutTerminatesTheProcess() async throws {
        let started = Date()
        let result = try await LiveProcessRunner().run(ProcessStep(executable: "/bin/sleep", arguments: ["30"]), timeout: .milliseconds(300))
        #expect(result.status != 0)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func missingExecutableThrows() async {
        await #expect(throws: (any Error).self) {
            try await LiveProcessRunner().run(ProcessStep(executable: "/nonexistent/rh-test-binary"))
        }
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let result = try await LiveProcessRunner().run(ProcessStep(executable: "/bin/sh", arguments: ["-c", "head -c 400000 /dev/zero | tr '\\0' 'x'"]))
        #expect(result.standardOutput.count == 400_000)
    }
}
