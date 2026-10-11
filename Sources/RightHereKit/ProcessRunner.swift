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

        // Drain both pipes while the process runs so a chatty child cannot fill a pipe and block.
        let outputTask = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let errorTask = Task.detached { error.fileHandleForReading.readDataToEndOfFile() }

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
            try? output.fileHandleForWriting.close()
            try? error.fileHandleForWriting.close()
            throw failure
        }
        return ProcessResult(
            status: status,
            standardOutput: String(decoding: await outputTask.value, as: UTF8.self),
            standardError: String(decoding: await errorTask.value, as: UTF8.self)
        )
    }
}

private final class LaunchFailure: @unchecked Sendable {
    var error: (any Error)?
}
