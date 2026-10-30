import AppKit
import Foundation
import RightHereCore

public enum ExecutionError: Error, Equatable, Sendable, LocalizedError {
    case stepFailed(index: Int, step: String, message: String)
    /// macOS refused to let the caller control an application (Automation permission).
    case automationDenied(application: String?)
    case fileExists(path: String)
    /// A step was stopped because it ran past its limit; most often macOS is waiting for the person to answer a
    /// permission prompt.
    case timedOut(step: String, seconds: Int)

    /// What a step says is what a program, a file or git wrote (git's own words name branches and paths), so the line breaks stay and every other control or
    /// invisible character is shown as an escape.
    public var errorDescription: String? {
        let text: String
        switch self {
        case .stepFailed(let index, let step, let message):
            text = "Step \(index + 1) (\(step)) failed: \(message)"
        case .automationDenied(let application):
            let target = application.map { " \($0)" } ?? " the application"
            text = "macOS blocked controlling\(target). Allow it in System Settings › Privacy & Security › Automation, then try again."
        case .fileExists(let path):
            text = "\(path) already exists."
        case .timedOut(let step, let seconds):
            text = "\(step) did not finish within \(seconds) seconds and was stopped. If macOS is waiting for you to allow Right Here to control an app (a permission prompt), answer it and try again."
        }
        return text.escapingControlCharacters(keeping: ["\n"])
    }
}

public protocol PasteboardWriting: Sendable {
    func write(_ text: String)
}

public struct SystemPasteboard: PasteboardWriting {
    public init() {}

    public func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// What running a plan produced, step by step.
public struct ExecutionReport: Sendable, Equatable, Codable {
    public struct StepReport: Sendable, Equatable, Codable {
        public var description: String
        public var output: String?
    }

    public var steps: [StepReport]
}

/// Carries out a `LaunchPlan` on the real machine. Stops at the first step that fails.
public struct LiveExecutor: Sendable {
    private let runner: any ProcessRunner
    private let pasteboard: any PasteboardWriting

    public init(runner: any ProcessRunner = LiveProcessRunner(), pasteboard: any PasteboardWriting = SystemPasteboard()) {
        self.runner = runner
        self.pasteboard = pasteboard
    }

    @discardableResult
    public func execute(_ plan: LaunchPlan) async throws -> ExecutionReport {
        var reports: [ExecutionReport.StepReport] = []
        for (index, step) in plan.steps.enumerated() {
            do {
                let output = try await perform(step)
                reports.append(.init(description: step.summary, output: output))
            } catch let error as ExecutionError {
                // The helpers below do not know their position in the plan.
                if case .stepFailed(_, let description, let message) = error { throw ExecutionError.stepFailed(index: index, step: description, message: message) }
                throw error
            } catch {
                throw ExecutionError.stepFailed(index: index, step: step.summary, message: error.localizedDescription)
            }
        }
        return ExecutionReport(steps: reports)
    }

    /// Where `open` runs. Its man page says it takes a URL that also matches a file path for that file (`-u` says otherwise), and
    /// `warp://action/…` read as a path is `warp:/action/…` under the working directory, which a cloned repository can hold: `rh` run in
    /// it would hand the terminal that file. In `/` no such folder can be made without an administrator.
    static let openDirectory = "/"

    private func perform(_ step: Step) async throws -> String? {
        switch step {
        case .open(let open):
            var arguments: [String] = []
            if !open.activate { arguments.append("-g") }
            if let bundleID = open.bundleID { arguments += ["-b", bundleID] }
            arguments += open.targets
            return try await check(ProcessStep(executable: "/usr/bin/open", arguments: arguments, currentDirectory: Self.openDirectory), step: step)

        case .openURL(let url):
            return try await check(ProcessStep(executable: "/usr/bin/open", arguments: [url], currentDirectory: Self.openDirectory), step: step)

        case .run(let process):
            return try await check(process, step: step)

        case .appleScript(let script):
            let process = ProcessStep(executable: "/usr/bin/osascript", arguments: ["-"] + script.arguments, standardInput: script.source)
            return try await check(process, step: step, controls: script.controls)

        case .copyToPasteboard(let text):
            pasteboard.write(text)
            return nil

        case .createFile(let file):
            try Self.createFile(file)
            return nil

        case .reveal(let paths):
            return try await check(ProcessStep(executable: "/usr/bin/open", arguments: ["-R"] + paths, currentDirectory: Self.openDirectory), step: step)

        case .pause(let milliseconds):
            try await Task.sleep(for: .milliseconds(milliseconds))
            return nil
        }
    }

    private func check(_ process: ProcessStep, step: Step, controls: String? = nil) async throws -> String? {
        let result = try await runner.run(process)
        if let limit = result.terminatedAfter {
            throw ExecutionError.timedOut(step: step.summary, seconds: Int(limit.components.seconds))
        }
        guard result.status == 0 else {
            if result.standardError.contains("(-1743)") { throw ExecutionError.automationDenied(application: controls) }
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ExecutionError.stepFailed(index: 0, step: step.summary, message: message.isEmpty ? "exit status \(result.status)" : message)
        }
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    /// Creates the file only if it does not exist, so a name chosen while planning cannot overwrite
    /// a file that appeared in the meantime.
    static func createFile(_ file: CreateFileStep) throws {
        let descriptor = Darwin.open(file.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw ExecutionError.fileExists(path: file.path) }
            throw ExecutionError.stepFailed(index: 0, step: "create \(file.path)", message: String(cString: strerror(errno)))
        }
        defer { Darwin.close(descriptor) }
        let bytes = file.bytes
        var written = 0
        while written < bytes.count {
            let count = bytes[written...].withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            guard count > 0 else {
                throw ExecutionError.stepFailed(index: 0, step: "create \(file.path)", message: String(cString: strerror(errno)))
            }
            written += count
        }
    }
}
