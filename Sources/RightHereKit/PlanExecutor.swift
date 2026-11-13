import AppKit
import Foundation
import RightHereCore

public enum ExecutionError: Error, Equatable, Sendable, LocalizedError, LocalizedFailure {
    case stepFailed(index: Int, step: String, message: String)
    /// macOS refused to let the caller control an application (Automation permission).
    case automationDenied(application: String?)
    case fileExists(path: String)
    /// A step was stopped because it ran past its limit; most often macOS is waiting for the person to answer a
    /// permission prompt.
    case timedOut(step: String, seconds: Int)
    /// There is no git to start (`GitCommand.gitIsInstalled`).
    case gitNotInstalled

    public var errorDescription: String? {
        text(in: .english)
    }

    public var sentences: [LocalizedMessage] {
        switch self {
        case .stepFailed(let index, let step, let message): [.refusalStepFailed(String(index + 1), step, message)]
        case .automationDenied(let application?): [.alertPermissionMessage(application)]
        case .automationDenied(nil): [.refusalAutomationDenied]
        case .fileExists(let path): [.refusalFileExists(path)]
        case .timedOut(let step, let seconds): [.refusalTimedOut(step, String(seconds))]
        case .gitNotInstalled: [.refusalGitNotInstalled]
        }
    }

    /// What a step says is what a program, a file or git wrote (git's own words name branches and paths), so its line breaks and tabs stay and every
    /// other control or invisible character is shown as an escape. The step's own name is Right Here's, and may hold a path: a line break in a folder's
    /// name would add a line of its own to the alert, so it is escaped whole.
    public var shownSentences: [LocalizedMessage] {
        guard case .stepFailed(let index, let step, let message) = self else { return sentences.map { $0.escapingValues() } }
        return [.refusalStepFailed(String(index + 1), step.withControlCharactersEscaped, message.escapingControlCharacters(keeping: ["\n", "\t"]))]
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

    /// How many plans New File makes in all when another run keeps taking the name it chose.
    static let newFileAttempts = 5

    /// Runs `plan`, and plans it again when another run took the name of the file it makes after it was planned (two clicks of New File, or a
    /// Quick Action and a Shortcut, at once): the new plan takes the next free name. Nothing has run then, since that file is the plan's first
    /// step; any other step that meets a file in its way fails as it did. A plan made again that names the same file fails too, rather than
    /// trying it once more. Returns the plan that ran, whose file is the one that was made.
    public func execute(_ plan: LaunchPlan, replanning replan: () throws -> LaunchPlan) async throws -> (plan: LaunchPlan, report: ExecutionReport) {
        var plan = plan
        var attempts = 1
        while true {
            do {
                return (plan, try await execute(plan))
            } catch ExecutionError.fileExists(let path) {
                guard attempts < Self.newFileAttempts, case .createFile(let file)? = plan.steps.first, file.path == path else { throw ExecutionError.fileExists(path: path) }
                let next = try replan()
                guard case .createFile(let nextFile)? = next.steps.first, nextFile.path != path else { throw ExecutionError.fileExists(path: path) }
                plan = next
                attempts += 1
            }
        }
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
    static func createFile(_ file: CreateFileStep,
                           write: (Int32, UnsafeRawPointer?, Int) -> Int = { Darwin.write($0, $1, $2) },
                           close: (Int32) -> Int32 = { Darwin.close($0) }) throws {
        let descriptor = Darwin.open(file.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw ExecutionError.fileExists(path: file.path) }
            throw ExecutionError.stepFailed(index: 0, step: Step.createFile(file).summary, message: String(cString: strerror(errno)))
        }
        var closed = false
        defer { if !closed { _ = close(descriptor) } }
        let bytes = file.bytes
        var written = 0
        while written < bytes.count {
            let count = bytes[written...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                let reason = count < 0 ? String(cString: strerror(errno)) : "nothing more could be written"
                // A full disk or a quota ends the write part-way: the file is this action's own (O_EXCL made it), and part of a document is no document.
                Darwin.unlink(file.path)
                throw ExecutionError.stepFailed(index: 0, step: Step.createFile(file).summary, message: reason)
            }
            written += count
        }
        // The last of the data may only be refused when the file is closed (a network volume, a quota): a file that was reported as made and holds part of a document is worse than none.
        closed = true
        if close(descriptor) != 0 {
            let reason = String(cString: strerror(errno))
            Darwin.unlink(file.path)
            throw ExecutionError.stepFailed(index: 0, step: Step.createFile(file).summary, message: reason)
        }
    }
}
