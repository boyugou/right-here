import Foundation
import RightHereCore

public struct ProcessResult: Sendable, Equatable {
    public var status: Int32
    public var standardOutput: String
    public var standardError: String

    public init(status: Int32, standardOutput: String = "", standardError: String = "") {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
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
        let watchdog = timeout.map { limit in
            Task.detached {
                try? await Task.sleep(for: limit)
                if !Task.isCancelled, process.isRunning { process.terminate() }
            }
        }
        defer { watchdog?.cancel() }
        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
                if let text = step.standardInput {
                    input.fileHandleForWriting.write(Data(text.utf8))
                    try? input.fileHandleForWriting.close()
                }
            } catch {
                launchFailure.error = error
                continuation.resume(returning: -1)
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
            standardError: String(decoding: errorCollector.collected, as: UTF8.self)
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
