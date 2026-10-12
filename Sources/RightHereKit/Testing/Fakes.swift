import Foundation
import RightHereCore

/// Test doubles for code that runs processes or writes the clipboard. They live in the library so
/// every test target can share them.

/// Records every process it is asked to run and answers from a script of results.
public final class FakeProcessRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [ProcessStep] = []
    private var results: [ProcessResult]

    public init(results: [ProcessResult] = []) {
        self.results = results
    }

    public var recorded: [ProcessStep] {
        lock.withLock { calls }
    }

    public func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        lock.withLock {
            calls.append(step)
            return results.isEmpty ? ProcessResult(status: 0) : results.removeFirst()
        }
    }
}

public final class RecordingPasteboard: PasteboardWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []

    public init() {}

    public var written: [String] {
        lock.withLock { texts }
    }

    public func write(_ text: String) {
        lock.withLock { texts.append(text) }
    }
}
