import Foundation
import RightHereCore
import Synchronization

public struct ProcessResult: Sendable, Equatable {
    public var status: Int32
    public var standardOutput: String
    public var standardError: String
    /// Set when the process was stopped for running past its limit (the limit it was given). `status` then says
    /// how it died, not what it would have answered.
    public var terminatedAfter: Duration?

    public init(status: Int32, standardOutput: String = "", standardError: String = "", terminatedAfter: Duration? = nil) {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.terminatedAfter = terminatedAfter
    }
}

/// Runs an executable with an argument vector. Replaceable in tests.
public protocol ProcessRunner: Sendable {
    /// - Parameter timeout: The process is terminated when it runs longer; `nil` waits indefinitely.
    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult
}

extension ProcessRunner {
    public func run(_ step: ProcessStep) async throws -> ProcessResult {
        try await run(step, timeout: nil)
    }
}

/// What `RH_NO_UI` refuses to start.
public struct UIDisabledError: Error, Equatable, LocalizedError {
    public let executable: String
    public var errorDescription: String? {
        "RH_NO_UI is set, so rh will not start \(executable): nothing may open a window, start an app or send an Apple event."
    }
}

public struct LiveProcessRunner: ProcessRunner {
    /// With `RH_NO_UI` set, the two programs that put something on a screen (`open`, which starts an app or a window,
    /// and `osascript`, which sends Apple events) are never started. The tests set it, so a test that goes wrong
    /// cannot open a window or control a terminal; the one place that does that on purpose, `rh doctor --probe-launch`,
    /// is run by hand without it.
    static let screenPrograms: Set<String> = ["/usr/bin/open", "/usr/bin/osascript"]

    private let environment: [String: String]

    /// Programs that start another program from their arguments; with `RH_NO_UI` any of them naming a screen
    /// program is refused too, since parsing every option of `env` or a shell is a losing game.
    static let launchers: Set<String> = ["env", "sh", "bash", "zsh", "dash", "ksh", "fish", "arch", "xcrun", "nohup", "caffeinate", "sudo", "time", "exec"]

    /// The screen program a step would start, however it is spelled (`/usr/bin//open`, `/USR/BIN/OPEN`,
    /// `/usr/bin/env -u X open`, `sh -c "open x"`). The check is on lower-cased names, the default volume ignores case.
    static func screenProgram(of step: ProcessStep) -> String? {
        func standard(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path.lowercased() }
        let names = ["open": "/usr/bin/open", "osascript": "/usr/bin/osascript"]
        let executable = standard(step.executable)
        if screenPrograms.contains(executable) { return executable }
        guard launchers.contains(executable.split(separator: "/").last.map(String.init) ?? executable) else { return nil }
        for argument in step.arguments {
            for word in argument.lowercased().split(whereSeparator: { " \t\n;|&()`'\"=".contains($0) }) {
                let text = String(word)
                if let found = names[text] ?? (screenPrograms.contains(standard(text)) ? standard(text) : nil) { return found }
            }
        }
        return nil
    }

    /// How long to keep reading after the process has exited. A child that was left running in the
    /// background (a shell startup file doing `(sleep 30 &)`) inherits the pipes and holds them open
    /// long after the process we started is gone; waiting for end-of-file would wait for it too.
    static let drainGrace: Duration = .milliseconds(300)

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    /// After a timeout: SIGKILL for a process that is still running, and for its process group when it leads
    /// one (it does, for what `Process` starts), so background children of a startup file die with it.
    static func killLeftovers(of process: Process) {
        let pid = process.processIdentifier
        guard pid > 1 else { return }
        if process.isRunning { kill(pid, SIGKILL) }
        if pid != getpgrp() { killpg(pid, SIGKILL) }
    }

    public func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        if environment["RH_NO_UI"] != nil, let program = Self.screenProgram(of: step) {
            throw UIDisabledError(executable: program)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: step.executable)
        process.arguments = step.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(step.environment) { $1 }
        if let directory = step.currentDirectory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }

        let output = Pipe()
        let error = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = step.standardInput == nil ? FileHandle.nullDevice : input

        // Collect both pipes while the process runs so a chatty child cannot fill a pipe and block.
        let outputCollector = PipeCollector(output.fileHandleForReading)
        let errorCollector = PipeCollector(error.fileHandleForReading)

        let launchFailure = LaunchFailure()
        let cutOff = CutOff()
        let watchdog = timeout.map { limit in
            Task.detached {
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled, process.isRunning else { return }
                cutOff.mark()
                process.terminate()
                // An interactive login shell ignores SIGTERM, so a startup file that never returns would hold
                // the caller forever: give it a moment, then kill it and whatever it left in its group.
                try? await Task.sleep(for: .seconds(1))
                Self.killLeftovers(of: process)
            }
        }
        defer {
            if cutOff.happened {
                Self.killLeftovers(of: process)
            }
            watchdog?.cancel()
        }
        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                launchFailure.error = error
                continuation.resume(returning: -1)
                return
            }
            if let text = step.standardInput {
                // Written on a Dispatch thread, not the Swift concurrency pool: a child that does not read leaves
                // `write` blocked, and blocked pool threads are the ones the watchdogs (and everything else
                // `async`) need to get the child stopped. Written without SIGPIPE: a process that exits before it
                // reads its input must not take this one down with it.
                let writer = input.fileHandleForWriting
                _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
                DispatchQueue.global(qos: .userInitiated).async {
                    do { try writer.write(contentsOf: Data(text.utf8)) } catch {}
                    try? writer.close()
                }
            }
        }
        if let failure = launchFailure.error {
            outputCollector.stop()
            errorCollector.stop()
            try? output.fileHandleForWriting.close()
            try? error.fileHandleForWriting.close()
            throw failure
        }
        await outputCollector.waitForEnd(upTo: Self.drainGrace)
        await errorCollector.waitForEnd(upTo: Self.drainGrace)
        outputCollector.stop()
        errorCollector.stop()
        return ProcessResult(
            status: status,
            standardOutput: String(decoding: outputCollector.collected, as: UTF8.self),
            standardError: String(decoding: errorCollector.collected, as: UTF8.self),
            terminatedAfter: cutOff.happened ? timeout : nil
        )
    }
}

/// Accumulates what a pipe delivers, and notices when every writer has closed it.
private final class PipeCollector: Sendable {
    private struct State {
        var data = Data()
        var reachedEnd = false
    }

    private let handle: FileHandle
    private let state = Mutex(State())

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] source in
            let chunk = source.availableData
            guard let self else { return }
            if chunk.isEmpty {
                source.readabilityHandler = nil
                self.state.withLock { $0.reachedEnd = true }
            } else {
                self.state.withLock { $0.data.append(chunk) }
            }
        }
    }

    var collected: Data { state.withLock { $0.data } }

    /// Returns as soon as the pipe reaches its end, or after `limit`.
    func waitForEnd(upTo limit: Duration) async {
        let deadline = ContinuousClock.now + limit
        while !state.withLock({ $0.reachedEnd }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func stop() {
        handle.readabilityHandler = nil
        try? handle.close()
    }
}

private final class LaunchFailure: @unchecked Sendable {
    var error: (any Error)?
}

/// Whether the watchdog stopped the process, written by the watchdog's task and read once the process is gone.
private final class CutOff: Sendable {
    private let fired = Mutex(false)

    func mark() { fired.withLock { $0 = true } }
    var happened: Bool { fired.withLock { $0 } }
}

/// Holds every process to `limit` at most: one that has no limit of its own gets it, and one whose own limit is longer gets it too. So a step that waits
/// for a person (an Apple event held up by a permission prompt) cannot hold its caller, and an MCP server's request slot, for longer than the server allows.
public struct TimeLimitedRunner: ProcessRunner {
    public let base: any ProcessRunner
    public let limit: Duration

    public init(base: any ProcessRunner, limit: Duration) {
        self.base = base
        self.limit = limit
    }

    public func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        try await base.run(step, timeout: timeout.map { min($0, limit) } ?? limit)
    }
}
