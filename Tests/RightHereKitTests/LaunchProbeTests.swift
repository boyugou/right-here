import Foundation
import Testing
@testable import RightHereCore
@testable import RightHereKit

/// Stands in for a terminal. When it is asked to run the AppleScript that starts a session it acts
/// like the new shell would: it runs the typed command in a real shell, in the folder it was given.
private final class FakeTerminal: ProcessRunner, @unchecked Sendable {
    enum Behavior {
        /// The typed command runs in a real shell (`/bin/sh`, `/bin/bash`, `/bin/zsh`).
        case runsTypedCommand(shell: String)
        /// A session opens, but nothing runs.
        case ignoresTypedCommand
        /// The command runs, but in another folder.
        case runsInAnotherFolder
        case answers(ProcessResult, after: Duration)
    }

    private let behavior: Behavior
    private let lock = NSLock()
    private var calls: [ProcessStep] = []
    private var timeouts: [Duration?] = []

    init(_ behavior: Behavior) { self.behavior = behavior }

    var recorded: [ProcessStep] { lock.withLock { calls } }
    /// The `timeout` each call was given, so a test can see that the probe bounds what it runs.
    var recordedTimeouts: [Duration?] { lock.withLock { timeouts } }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        lock.withLock { calls.append(step); timeouts.append(timeout) }
        guard step.executable == "/usr/bin/osascript", step.arguments.count >= 2 else { return ProcessResult(status: 0) }
        // Ghostty is given the folder and the command separately; Terminal.app one line that starts with `cd`.
        let handedTheFolder = step.arguments.count >= 3
        let folder = handedTheFolder ? step.arguments[1] : FileManager.default.temporaryDirectory.path
        let typed = handedTheFolder ? step.arguments[2] : step.arguments[1]
        switch behavior {
        case .runsTypedCommand(let shell):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-c", typed]
            process.currentDirectoryURL = URL(fileURLWithPath: folder)
            process.environment = ["SHELL": "/bin/the-login-shell", "PATH": "/usr/bin:/bin"]
            try process.run()
            process.waitUntilExit()
        case .ignoresTypedCommand:
            break
        case .runsInAnotherFolder:
            try "/bin/the-login-shell\n/somewhere/else\n".write(toFile: folder + "/" + LaunchProbe.markerName, atomically: true, encoding: .utf8)
        case .answers(let result, let delay):
            try await Task.sleep(for: delay)
            return result
        }
        return ProcessResult(status: 0)
    }
}

private let ghostty = KnownApps.terminal(id: "ghostty")!
private let appleTerminal = KnownApps.terminal(id: "terminal")!

@Suite("LaunchProbe")
struct LaunchProbeTests {
    /// The probe's folder depends only on the root and the token, so a first instance names it and
    /// the facts of the real one know it as a folder.
    private func makeProbe(_ terminal: FakeTerminal, root: URL, executionLimit: Duration = .seconds(25), typesTheFolder: Bool = false) -> LaunchProbe {
        let folder = LaunchProbe(scratchRoot: root, token: "test").folder(typesTheFolder: typesTheFolder)
        return LaunchProbe(
            facts: FakeSystemFacts(directories: [folder.path]),
            runner: terminal, scratchRoot: root, token: "test", executionLimit: executionLimit
        )
    }

    @Test("the typed command runs in every common shell, in the folder it was started in", arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"])
    func ranInARealShell(shell: String) async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let terminal = FakeTerminal(.runsTypedCommand(shell: shell))
        let probe = makeProbe(terminal, root: root)
        let result = await probe.run(terminal: ghostty, bundleID: "com.mitchellh.ghostty", timeout: .seconds(5))
        #expect(result.outcome == .ran, "\(result)")
        #expect(result.application == "Ghostty")
        #expect(result.shell == "/bin/the-login-shell")
        #expect(result.seconds != nil)
    }

    @Test("Terminal.app's typed line `cd '…' && command` runs in a real shell, in the awkward folder",
          arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"])
    func terminalAppRanInARealShell(shell: String) async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let terminal = FakeTerminal(.runsTypedCommand(shell: shell))
        let probe = makeProbe(terminal, root: root, typesTheFolder: true)
        let result = await probe.run(terminal: appleTerminal, bundleID: "com.apple.Terminal", timeout: .seconds(5))
        #expect(result.outcome == .ran, "\(result)")
        let call = try #require(terminal.recorded.first)
        let line = try #require(call.arguments.last)
        #expect(line.hasPrefix("cd '"), "the line was \(line)")
        #expect(call.arguments.count == 2, "Terminal.app gets one argument, the whole line")
    }

    @Test func aTerminalThatTypesTheFolderIsProbedWithAFolderNameItWillAccept() async throws {
        let typing = LaunchProbe(scratchRoot: URL(fileURLWithPath: "/tmp"), token: "t").folder(typesTheFolder: true).lastPathComponent
        let handed = LaunchProbe(scratchRoot: URL(fileURLWithPath: "/tmp"), token: "t").folder().lastPathComponent
        #expect(!typing.contains("\\"), "Terminal.app refuses a backslash")
        #expect(handed.contains("\\"))
        for fragment in [" ", "'", "\"", "$", "`", ";", "&", "|"] { #expect(typing.contains(fragment), "missing \(fragment)") }
    }

    @Test func theProbeBoundsEveryProcessItRuns() async throws {
        // Without a limit a step waiting on a permission prompt would hang the probe, and `rh`, forever.
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let terminal = FakeTerminal(.runsTypedCommand(shell: "/bin/sh"))
        let probe = makeProbe(terminal, root: root, executionLimit: .seconds(7))
        _ = await probe.run(terminal: ghostty, bundleID: "com.mitchellh.ghostty", timeout: .seconds(5))
        #expect(!terminal.recordedTimeouts.isEmpty)
        #expect(terminal.recordedTimeouts.allSatisfy { $0 == .seconds(7) }, "\(terminal.recordedTimeouts)")
    }

    @Test func theSessionGoesThroughTheTerminalAdapterWithTheFolderAndTheCommandAsArguments() async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let terminal = FakeTerminal(.runsTypedCommand(shell: "/bin/sh"))
        let probe = makeProbe(terminal, root: root)
        _ = await probe.run(terminal: ghostty, bundleID: "com.mitchellh.ghostty", timeout: .seconds(5))
        let call = try #require(terminal.recorded.first)
        #expect(call.executable == "/usr/bin/osascript")
        #expect(call.standardInput == GhosttyAdapter.script)
        #expect(Array(call.arguments.dropFirst()) == [probe.folder().path, LaunchProbe.command, "window"])
    }

    @Test func theFolderNameIsAwkwardOnPurposeAndIsRemovedAfterwards() async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let terminal = FakeTerminal(.runsTypedCommand(shell: "/bin/sh"))
        let probe = makeProbe(terminal, root: root)
        let name = probe.folder().lastPathComponent
        for fragment in [" ", "'", "\"", "\\", "$", "`", ";", "&", "|"] { #expect(name.contains(fragment), "missing \(fragment)") }
        _ = await probe.run(terminal: ghostty, bundleID: "com.mitchellh.ghostty", timeout: .seconds(5))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func aCommandThatRanElsewhereIsReported() async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let probe = makeProbe(FakeTerminal(.runsInAnotherFolder), root: root)
        let result = await probe.run(terminal: ghostty, bundleID: "com.mitchellh.ghostty", timeout: .seconds(5))
        #expect(result.outcome == .wrongFolder)
        #expect(result.detail?.contains("/somewhere/else") == true)
    }

    @Test func aCommandThatNeverRunsIsNoReply() async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let probe = makeProbe(FakeTerminal(.ignoresTypedCommand), root: root)
        let result = await probe.run(terminal: ghostty, bundleID: "com.mitchellh.ghostty", timeout: .milliseconds(500))
        #expect(result.outcome == .noReply)
    }

    @Test func aRefusedAppleEventIsDenied() async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let refusal = ProcessResult(status: 1, standardError: "execution error: Not authorized to send Apple events to Ghostty. (-1743)")
        let probe = makeProbe(FakeTerminal(.answers(refusal, after: .zero)), root: root)
        let result = await probe.run(terminal: ghostty, bundleID: "com.mitchellh.ghostty", timeout: .seconds(1))
        #expect(result.outcome == .denied)
    }

    @Test func anAppleEventCutOffAtTheLimitMeansNobodyAnsweredThePrompt() async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let cutOff = ProcessResult(status: 15, terminatedAfter: .seconds(2))
        let probe = makeProbe(FakeTerminal(.answers(cutOff, after: .milliseconds(100))), root: root, executionLimit: .seconds(2))
        let result = await probe.run(terminal: ghostty, bundleID: "com.mitchellh.ghostty", timeout: .seconds(1))
        #expect(result.outcome == .timedOut)
    }

    @Test func aProcessThatDiedQuicklyOnItsOwnIsNeverReadAsATimeout() async throws {
        // The old test for this guessed from how long the step took; a slow failure looked like a time-out.
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let slowFailure = ProcessResult(status: 1, standardError: "syntax error")
        let probe = makeProbe(FakeTerminal(.answers(slowFailure, after: .milliseconds(1_300))), root: root, executionLimit: .seconds(2))
        let result = await probe.run(terminal: ghostty, bundleID: "com.mitchellh.ghostty", timeout: .seconds(1))
        #expect(result.outcome == .failed, "\(result)")
    }

    @Test func aQuickFailureIsAFailureNotATimeout() async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let failure = ProcessResult(status: 1, standardError: "syntax error")
        let probe = makeProbe(FakeTerminal(.answers(failure, after: .zero)), root: root)
        let result = await probe.run(terminal: ghostty, bundleID: "com.mitchellh.ghostty", timeout: .seconds(1))
        #expect(result.outcome == .failed)
        #expect(result.detail?.contains("syntax error") == true)
    }

    @Test func aTerminalThatCannotRunCommandsIsNotProbed() async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let terminal = FakeTerminal(.ignoresTypedCommand)
        let probe = LaunchProbe(facts: FakeSystemFacts(), runner: terminal, scratchRoot: root)
        let result = await probe.run(terminal: KnownApps.terminal(id: "warp")!, bundleID: "dev.warp.Warp-Stable", timeout: .seconds(1))
        #expect(result.outcome == .unsupported)
        #expect(terminal.recorded.isEmpty)
    }

    @Test func theResultRoundTripsThroughTheLog() throws {
        let result = LaunchProbe.Result(application: "Ghostty", outcome: .noReply, seconds: 1.5, shell: "/bin/zsh", detail: "d")
        let decoded = try JSONDecoder().decode(LaunchProbe.Result.self, from: JSONEncoder().encode(result))
        #expect(decoded == result)
    }

    @Test func theTypedCommandHasNoControlCharacters() throws {
        try ShellQuoting.validateForTyping(LaunchProbe.command)
    }
}
