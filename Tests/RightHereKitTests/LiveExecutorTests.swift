import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("LiveExecutor")
struct LiveExecutorTests {
    private func executor(_ runner: FakeProcessRunner, _ pasteboard: RecordingPasteboard = RecordingPasteboard()) -> LiveExecutor {
        LiveExecutor(runner: runner, pasteboard: pasteboard)
    }

    /// What a step says is what a program wrote (git's own words name branches and paths): its line breaks stay, and a terminal escape or a character that draws nothing is shown.
    @Test func whatAStepSaysHasItsControlAndInvisibleCharactersShownAsEscapes() {
        let description = ExecutionError.stepFailed(index: 0, step: "git worktree remove", message: "fatal: 'x\u{1b}]0;t\u{07}y\u{202E}' is dirty\nhint: use --force\u{200B}").errorDescription ?? ""
        #expect(description == "Step 1 (git worktree remove) failed: fatal: 'x\\u001b]0;t\\u0007y\\u202e' is dirty\nhint: use --force\\u200b")
        for error in [ExecutionError.fileExists(path: "/a\u{1b}b"), .automationDenied(application: "T\u{9b}"), .timedOut(step: "run\u{1b}", seconds: 3)] {
            #expect(!(error.errorDescription ?? "").unicodeScalars.contains { $0.properties.generalCategory == .control }, "\(error)")
        }
    }

    @Test func openRunsLaunchServicesWithTheBundleId() async throws {
        let runner = FakeProcessRunner()
        let plan = LaunchPlan(action: "t", summary: "t", steps: [.open(OpenStep(bundleID: "com.apple.Terminal", targets: ["/tmp/a b"]))])
        try await executor(runner).execute(plan)
        #expect(runner.recorded == [ProcessStep(executable: "/usr/bin/open", arguments: ["-b", "com.apple.Terminal", "/tmp/a b"], currentDirectory: "/")])
    }

    /// `open` takes an argument that also names a file in its working directory for that file, and `warp://action/…` is the relative path
    /// `warp:/action/…`, which a cloned repository can hold: run from that folder, `rh` would hand the terminal the file.
    @Test func openRunsInTheRootFolderSoThatALinkIsNeverAFileOfTheFolderRhRunsIn() async throws {
        let runner = FakeProcessRunner()
        let steps: [Step] = [.open(OpenStep(bundleID: "dev.warp.Warp-Stable", targets: ["warp://action/new_window?path=/tmp/x"])), .openURL("claude-cli://open?cwd=%2Ftmp"), .reveal(["/tmp/a"])]
        try await executor(runner).execute(LaunchPlan(action: "t", summary: "t", steps: steps))
        #expect(runner.recorded.count == 3)
        #expect(runner.recorded.allSatisfy { $0.executable == "/usr/bin/open" && $0.currentDirectory == "/" }, "\(runner.recorded)")
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

    @Test func aFailureNamesTheStepThatFailed() async {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0), ProcessResult(status: 1, standardError: "boom")])
        let plan = LaunchPlan(action: "t", summary: "t", steps: [.openURL("x://one"), .openURL("x://two")])
        do { try await executor(runner, RecordingPasteboard()).execute(plan); Issue.record("expected a failure") } catch ExecutionError.stepFailed(let index, _, _) {
            #expect(index == 1)
        } catch { Issue.record("unexpected \(error)") }
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

    @Test func anOfficeTemplateIsWrittenAsItsDocument() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("untitled.xlsx").path
        try await executor(FakeProcessRunner()).execute(LaunchPlan(action: "t", summary: "t", steps: [.createFile(CreateFileStep(path: path, format: .xlsx))]))
        #expect(try [UInt8](Data(contentsOf: URL(fileURLWithPath: path))) == OfficeDocument.bytes(.xlsx), "a workbook, not an empty file named .xlsx")
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

@Suite("LiveProcessRunner", .serialized)
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
        #expect(Date().timeIntervalSince(started) < 25)
    }

    @Test func aProcessStoppedForRunningTooLongSaysSoAndOneThatFinishedDoesNot() async throws {
        let stopped = try await LiveProcessRunner().run(ProcessStep(executable: "/bin/sleep", arguments: ["30"]), timeout: .milliseconds(300))
        #expect(stopped.terminatedAfter == .milliseconds(300))
        let finished = try await LiveProcessRunner().run(ProcessStep(executable: "/bin/echo", arguments: ["hi"]), timeout: .seconds(10))
        #expect(finished.terminatedAfter == nil)
        #expect(finished.standardOutput == "hi\n")
        // And a process that fails on its own, quickly, is a failure and not a time-out.
        let failed = try await LiveProcessRunner().run(ProcessStep(executable: "/usr/bin/false"), timeout: .seconds(10))
        #expect(failed.status != 0 && failed.terminatedAfter == nil)
    }

    @Test func aStepThatRanOutOfTimeIsReportedAsThatNotAsACrypticExitStatus() async throws {
        let runner = FakeProcessRunner(results: [ProcessResult(status: 15, terminatedAfter: .seconds(120))])
        let plan = LaunchPlan(action: "x", summary: "x", steps: [.appleScript(AppleScriptStep(source: "on run argv\nend run", controls: "Ghostty"))])
        do {
            try await LiveExecutor(runner: runner, pasteboard: RecordingPasteboard()).execute(plan)
            Issue.record("expected a time-out")
        } catch let error as ExecutionError {
            guard case .timedOut(_, let seconds) = error else { Issue.record("wrong error \(error)"); return }
            #expect(seconds == 120)
            #expect(error.localizedDescription.contains("permission"))
        }
    }

    @Test func theTimeLimitedRunnerGivesAProcessADefaultLimitButKeepsItsOwn() async throws {
        let recorder = LimitRecorder()
        let limited = TimeLimitedRunner(base: recorder, limit: .seconds(7))
        _ = try await limited.run(ProcessStep(executable: "/bin/echo"), timeout: nil)
        _ = try await limited.run(ProcessStep(executable: "/bin/echo"), timeout: .seconds(2))
        #expect(recorder.limits == [.seconds(7), .seconds(2)])
    }

    @Test func manyRunsWithInputToProcessesThatNeverReadStillTimeOutPromptly() async throws {
        // A child that does not read leaves the writer blocked in write(2). If the writers ran on the Swift
        // concurrency pool, as many of them as the pool has threads would keep the watchdog tasks that stop the
        // children from ever running, and every run would last as long as its child (here 30 seconds).
        let big = String(repeating: "x", count: 300_000)
        let runs = ProcessInfo.processInfo.activeProcessorCount * 2 + 4
        let started = ContinuousClock.now
        let stopped = await withTaskGroup(of: Bool.self) { group -> Int in
            for _ in 0..<runs {
                group.addTask {
                    let result = try? await LiveProcessRunner().run(ProcessStep(executable: "/bin/sleep", arguments: ["30"], standardInput: big), timeout: .seconds(1))
                    return result?.terminatedAfter != nil
                }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        let took = ContinuousClock.now - started
        #expect(stopped == runs && took < .seconds(25), "\(stopped) of \(runs) were stopped, after \(took)")
    }

    @Test("with RH_NO_UI set the programs that put something on a screen are never started", arguments: ["/usr/bin/open", "/usr/bin/osascript"])
    func noUIRefusesToStartScreenPrograms(executable: String) async throws {
        let runner = LiveProcessRunner(environment: ["RH_NO_UI": "1"])
        await #expect(throws: UIDisabledError(executable: executable)) {
            try await runner.run(ProcessStep(executable: executable, arguments: ["-b", "com.apple.Terminal"]))
        }
        // Everything else still runs.
        #expect(try await runner.run(ProcessStep(executable: "/bin/echo", arguments: ["fine"])).standardOutput == "fine\n")
    }

    @Test("RH_NO_UI sees through other spellings of open and osascript", arguments: [
        ("/usr/bin//open", [String]()), ("/usr/bin/../bin/osascript", []), ("/usr/bin/env", ["open", "-b", "x"]), ("/usr/bin/env", ["osascript"]),
        ("/usr/bin/OPEN", []), ("/USR/BIN/osascript", []), ("/usr/bin/env", ["-u", "FOO", "open", "x"]), ("/usr/bin/env", ["-S", "open x"]),
        ("/bin/sh", ["-c", "open x"]), ("/usr/bin/arch", ["-arm64", "open"]), ("/bin/zsh", ["-lc", "cd /tmp; osascript -e x"])
    ])
    func noUISeesThroughSpellings(executable: String, arguments: [String]) async {
        let runner = LiveProcessRunner(environment: ["RH_NO_UI": "1"])
        await #expect(throws: UIDisabledError.self) { try await runner.run(ProcessStep(executable: executable, arguments: arguments)) }
    }

    @Test func missingExecutableThrows() async {
        await #expect(throws: (any Error).self) {
            try await LiveProcessRunner().run(ProcessStep(executable: "/nonexistent/rh-test-binary"))
        }
    }

    @Test func aChildLeftRunningInTheBackgroundDoesNotHoldTheResultUp() async throws {
        // `(sleep 6 &)` is what a shell startup file can do: the sleep inherits the pipes and outlives the shell.
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await LiveProcessRunner().run(ProcessStep(executable: "/bin/sh", arguments: ["-c", "(sleep 6 &) ; echo done"]), timeout: .seconds(10))
        #expect(result.status == 0)
        #expect(result.standardOutput == "done\n")
        #expect(clock.now - started < .seconds(3), "waited for the background child")
    }

    @Test func theTimeoutHoldsWhenTheKilledProcessLeftAChildHoldingThePipes() async throws {
        let clock = ContinuousClock()
        let started = clock.now
        // The shell is terminated at the limit; its `sleep` keeps the pipes open.
        _ = try await LiveProcessRunner().run(ProcessStep(executable: "/bin/sh", arguments: ["-c", "sleep 8 & wait"]), timeout: .milliseconds(300))
        #expect(clock.now - started < .seconds(5), "took \(clock.now - started)")
    }

    @Test func aProcessThatIgnoresTerminateIsStillKilledAtTheLimit() async throws {
        // An interactive login shell ignores SIGTERM, so a rc file that never returns would hold a caller forever.
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await LiveProcessRunner().run(
            ProcessStep(executable: "/bin/sh", arguments: ["-c", "trap '' TERM; sleep 30"]), timeout: .milliseconds(300))
        #expect(clock.now - started < .seconds(20), "waited \(clock.now - started) for a process that ignores SIGTERM")
        #expect(result.status != 0)
    }

    @Test func theChildrenOfAKilledProcessAreKilledToo() async throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("child.pid")
        // The shell ignores SIGTERM and so does its background child, so only the hard kill of the whole group can end it.
        _ = try await LiveProcessRunner().run(
            ProcessStep(executable: "/bin/sh", arguments: ["-c", "trap '' TERM; sleep 60 & echo $! > '\(pidFile.path)'; wait"]), timeout: .seconds(2))
        // Judged by the child's own death, not by a clock: the group is killed right after the shell, and the test only
        // waits for the system to deliver it, however loaded the machine is.
        let text = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try #require(pid_t(text), "the shell did not record its child")
        var alive = true
        for _ in 0..<100 where alive {
            alive = kill(pid, 0) == 0
            if alive { try await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(!alive, "a child of the killed process kept running")
        if alive { kill(pid, SIGKILL) }
    }

    @Test func writingInputToAProcessThatAlreadyExitedNeverKillsTheCaller() async throws {
        for _ in 0..<300 {
            _ = try? await LiveProcessRunner().run(ProcessStep(executable: "/usr/bin/true", standardInput: String(repeating: "hello ", count: 20_000)))
        }
    }

    @Test func standardErrorIsCollectedSeparately() async throws {
        let result = try await LiveProcessRunner().run(ProcessStep(executable: "/bin/sh", arguments: ["-c", "echo out; echo err >&2; exit 3"]))
        #expect(result.status == 3)
        #expect(result.standardOutput == "out\n")
        #expect(result.standardError == "err\n")
    }

    @Test func aMegabyteOfOutputIsCollectedWhole() async throws {
        let result = try await LiveProcessRunner().run(ProcessStep(executable: "/bin/sh", arguments: ["-c", "head -c 1000000 /dev/zero | tr '\\0' 'y'"]))
        #expect(result.standardOutput.count == 1_000_000)
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let result = try await LiveProcessRunner().run(ProcessStep(executable: "/bin/sh", arguments: ["-c", "head -c 400000 /dev/zero | tr '\\0' 'x'"]))
        #expect(result.standardOutput.count == 400_000)
    }
}


private final class LimitRecorder: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Duration?] = []
    var limits: [Duration?] { lock.withLock { seen } }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        lock.withLock { seen.append(timeout) }
        return ProcessResult(status: 0)
    }
}
