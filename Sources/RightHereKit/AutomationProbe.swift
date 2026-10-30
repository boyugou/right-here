import Foundation
import RightHereCore

/// Checks whether the process this runs in may control another app. It sends one harmless Apple
/// event (`get name`), so macOS asks the person once if it has not been asked yet. The answer
/// belongs to the *calling* context: run from the Finder extension's runner it describes the
/// extension, run from a terminal it describes that terminal.
public struct AutomationProbe: Sendable {
    public enum Outcome: String, Sendable, Codable {
        case granted
        /// macOS refused, or the person said no. Without the entitlement a hardened app is refused
        /// without ever being asked.
        case denied
        /// Nobody answered the permission prompt in time.
        case timedOut = "timed-out"
        case notRunning = "not-running"
        case failed
    }

    public struct Result: Sendable, Equatable, Codable {
        public var application: String
        public var bundleID: String
        public var outcome: Outcome
        public var detail: String?

        public init(application: String, bundleID: String, outcome: Outcome, detail: String? = nil) {
            self.application = application
            self.bundleID = bundleID
            self.outcome = outcome
            self.detail = detail
        }
    }

    private let facts: any SystemFacts
    private let runner: any ProcessRunner

    public init(facts: any SystemFacts = LiveSystemFacts(), runner: any ProcessRunner = LiveProcessRunner()) {
        self.facts = facts
        self.runner = runner
    }

    /// Constant source; the bundle identifier arrives as an argument.
    static let script = """
    on run argv
        with timeout of 25 seconds
            tell application id (item 1 of argv) to get name
        end timeout
    end run
    """

    public func check(name: String, bundleID: String) async -> Result {
        guard facts.isRunning(bundleID: bundleID) else {
            return Result(application: name, bundleID: bundleID, outcome: .notRunning, detail: "\(name) is not running; it was not started.")
        }
        do {
            let result = try await runner.run(
                ProcessStep(executable: "/usr/bin/osascript", arguments: ["-", bundleID], standardInput: Self.script),
                timeout: .seconds(40)
            )
            if result.status == 0 { return Result(application: name, bundleID: bundleID, outcome: .granted) }
            let error = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let outcome: Outcome = error.contains("(-1743)") ? .denied : (error.contains("(-1712)") || result.terminatedAfter != nil) ? .timedOut : .failed
            return Result(application: name, bundleID: bundleID, outcome: outcome, detail: error)
        } catch {
            return Result(application: name, bundleID: bundleID, outcome: .failed, detail: error.localizedDescription)
        }
    }
}
