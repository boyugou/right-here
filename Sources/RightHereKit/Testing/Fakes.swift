import Foundation
import RightHereCore
import Synchronization

/// Test doubles for code that runs processes or writes the clipboard. They live in the library so
/// every test target can share them.

/// Records every process it is asked to run and answers from a script of results.
public final class FakeProcessRunner: ProcessRunner, Sendable {
    private struct State {
        var calls: [ProcessStep] = []
        var results: [ProcessResult]
    }

    private let state: Mutex<State>

    public init(results: [ProcessResult] = []) {
        state = Mutex(State(results: results))
    }

    public var recorded: [ProcessStep] {
        state.withLock { $0.calls }
    }

    public func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        state.withLock {
            $0.calls.append(step)
            return $0.results.isEmpty ? ProcessResult(status: 0) : $0.results.removeFirst()
        }
    }
}

public final class RecordingPasteboard: PasteboardWriting, Sendable {
    private let texts = Mutex<[String]>([])

    public init() {}

    public var written: [String] {
        texts.withLock { $0 }
    }

    public func write(_ text: String) {
        texts.withLock { $0.append(text) }
    }
}
