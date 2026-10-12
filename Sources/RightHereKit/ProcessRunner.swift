import Foundation
import RightHereCore

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

public struct LiveProcessRunner: ProcessRunner {
    /// How long to keep reading after the process has exited. A child that was left running in the
    /// background (a shell startup file doing `(sleep 30 &)`) inherits the pipes and holds them open
    /// long after the process we started is gone; waiting for end-of-file would wait for it too.
    static let drainGrace: Duration = .milliseconds(300)

    public init() {}

    /// After a timeout: SIGKILL for a process that is still running, and for its process group when it leads
    /// one (it does, for what `Process` starts), so background children of a startup file die with it.
    static func killLeftovers(of process: Process) {
        let pid = process.processIdentifier
        guard pid > 1 else { return }
        if process.isRunning { kill(pid, SIGKILL) }
        if pid != getpgrp(), getpgid(pid) == pid || !process.isRunning { killpg(pid, SIGKILL) }
    }

    public func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
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
        defer { watchdog?.cancel() }
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
                // Written off the cooperative pool, and without SIGPIPE: a process that exits before it reads
                // its input must not take this one down with it.
                let writer = input.fileHandleForWriting
                _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
                Task.detached {
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
private final class PipeCollector: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()
    private var reachedEnd = false

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] source in
            let chunk = source.availableData
            guard let self else { return }
            if chunk.isEmpty {
                source.readabilityHandler = nil
                self.lock.withLock { self.reachedEnd = true }
            } else {
                self.lock.withLock { self.data.append(chunk) }
            }
        }
    }

    var collected: Data { lock.withLock { data } }

    /// Returns as soon as the pipe reaches its end, or after `limit`.
    func waitForEnd(upTo limit: Duration) async {
        let deadline = ContinuousClock.now + limit
        while !lock.withLock({ reachedEnd }), ContinuousClock.now < deadline {
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
private final class CutOff: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func mark() { lock.withLock { fired = true } }
    var happened: Bool { lock.withLock { fired } }
}

/// Gives every process that has no limit of its own a default one, so a step that waits for a person (an Apple
/// event held up by a permission prompt) cannot hold its caller, and an MCP server's request slot, forever.
public struct TimeLimitedRunner: ProcessRunner {
    public let base: any ProcessRunner
    public let limit: Duration

    public init(base: any ProcessRunner, limit: Duration) {
        self.base = base
        self.limit = limit
    }

    public func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        try await base.run(step, timeout: timeout ?? limit)
    }
}
