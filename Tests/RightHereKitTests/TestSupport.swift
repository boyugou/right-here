import Foundation
import RightHereCore
@testable import RightHereKit

/// Records every process it is asked to run and answers from a script.
final class FakeRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [ProcessStep] = []
    private var results: [ProcessResult]

    init(results: [ProcessResult] = []) {
        self.results = results
    }

    var recorded: [ProcessStep] {
        lock.withLock { calls }
    }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        lock.withLock {
            calls.append(step)
            return results.isEmpty ? ProcessResult(status: 0) : results.removeFirst()
        }
    }
}

final class FakePasteboard: PasteboardWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []

    var written: [String] {
        lock.withLock { texts }
    }

    func write(_ text: String) {
        lock.withLock { texts.append(text) }
    }
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rh-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

enum Shell {
    /// Runs an executable and returns its standard output.
    static func run(_ executable: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
