import Foundation
import RightHereCore

/// Starts a throwaway session in a terminal and checks what it did: that the typed command ran
/// (the linefeed pressed Return), in the folder that was asked for, in the person's login shell.
/// This is the part of an agent launch that only a real terminal can answer.
///
/// The session goes through the same adapter and executor an agent launch uses. Its folder has an
/// awkward name (spaces, quotes, `$`, a backtick), so a quoting mistake shows up here instead of
/// in someone's project. The typed command writes a file and exits, so the window closes itself.
public struct LaunchProbe: Sendable {
    public enum Outcome: String, Sendable, Codable {
        /// The command ran in the right folder.
        case ran
        /// The terminal took the request, but the command did not report in time.
        case noReply = "no-reply"
        /// The command ran, but not in the folder that was asked for.
        case wrongFolder = "wrong-folder"
        /// macOS refused to let the caller control the terminal.
        case denied
        /// Nobody answered the permission prompt in time.
        case timedOut = "timed-out"
        case notInstalled = "not-installed"
        /// The terminal has no way to run a command.
        case unsupported
        case failed
    }

    public struct Result: Sendable, Equatable, Codable {
        public var application: String
        public var outcome: Outcome
        /// Seconds from the request until the command reported.
        public var seconds: Double?
        /// Seconds until the terminal accepted the request (the Apple event came back); the rest of
        /// `seconds` is the terminal and the shell starting up.
        public var accepted: Double?
        /// The login shell the new session reported (`$SHELL`).
        public var shell: String?
        public var detail: String?

        public init(application: String, outcome: Outcome, seconds: Double? = nil, accepted: Double? = nil, shell: String? = nil, detail: String? = nil) {
            self.application = application
            self.outcome = outcome
            self.seconds = seconds
            self.accepted = accepted
            self.shell = shell
            self.detail = detail
        }
    }

    /// The file the session writes, inside the throwaway folder.
    static let markerName = ".rh-probe-launch"
    /// Typed into the new shell. Fish accepts it as well as zsh and bash.
    static let command = "printf '%s\\n' \"$SHELL\" \"$PWD\" > \(markerName); exit"
    /// Spaces, both kinds of quote, a backslash (also directly before a quote, which fish reads as an
    /// escape), `$`, a backtick and shell punctuation.
    static let awkwardName = "a b'c\"d\\e\\' $HOME `x` ;&|"
    /// The same without the backslashes, for a terminal that types the folder into a shell: it refuses a
    /// backslash because shells read it differently, and the probe has to be able to start there.
    static let awkwardNameWithoutBackslash = "a b'c\"d' $HOME `x` ;&|"

    private let facts: any SystemFacts
    private let executor: LiveExecutor
    private let scratchRoot: URL
    private let token: String
    private let executionLimit: Duration

    /// - Parameters:
    ///   - scratchRoot: Where the throwaway folder is made.
    ///   - executionLimit: How long the Apple event may take. macOS can be waiting for the person to
    ///     answer a permission prompt, so it is bounded.
    public init(
        facts: any SystemFacts = LiveSystemFacts(),
        runner: any ProcessRunner = LiveProcessRunner(),
        scratchRoot: URL = FileManager.default.temporaryDirectory,
        token: String = String(UUID().uuidString.prefix(8)),
        executionLimit: Duration = .seconds(25)
    ) {
        self.facts = facts
        self.executor = LiveExecutor(runner: TimeLimitedRunner(base: runner, limit: executionLimit))
        self.scratchRoot = scratchRoot
        self.token = token
        self.executionLimit = executionLimit
    }

    /// The throwaway folder the session starts in (it exists only while `run` is working).
    func folder(typesTheFolder: Bool = false) -> URL {
        scratchRoot.appendingPathComponent("right-here-probe-\(token)")
            .appendingPathComponent(typesTheFolder ? Self.awkwardNameWithoutBackslash : Self.awkwardName)
    }

    /// Runs the probe in `app`, which must be installed under `bundleID`.
    public func run(terminal app: AppDescriptor, bundleID: String, placement: TerminalPlacement = .newWindow, timeout: Duration = .seconds(15)) async -> Result {
        let adapter = TerminalAdapters.adapter(for: app)
        if let refusal = adapter.commandRefusal {
            return Result(application: app.name, outcome: .unsupported, detail: refusal)
        }
        let folder = folder(typesTheFolder: adapter.typesTheFolder)
        let root = folder.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return Result(application: app.name, outcome: .failed, detail: error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let steps: [Step]
        do {
            steps = try adapter.steps(for: TerminalSession(directory: folder, typedInput: Self.command, placement: placement), bundleID: bundleID, facts: facts)
        } catch {
            return Result(application: app.name, outcome: .failed, detail: error.localizedDescription)
        }

        let clock = ContinuousClock()
        let started = clock.now
        do {
            try await executor.execute(LaunchPlan(action: "probe.launch", summary: "Probe \(app.name)", steps: steps))
        } catch ExecutionError.automationDenied {
            return Result(application: app.name, outcome: .denied)
        } catch ExecutionError.timedOut {
            // A step cut off at the limit means macOS never got an answer to its permission prompt.
            return Result(application: app.name, outcome: .timedOut, detail: "No answer to the permission prompt within \(executionLimit).")
        } catch {
            return Result(application: app.name, outcome: .failed, detail: error.localizedDescription)
        }

        let accepted = Self.seconds(clock.now - started)
        let marker = folder.appendingPathComponent(Self.markerName)
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let report = Self.read(marker) {
                let seconds = Self.seconds(clock.now - started)
                let sameFolder = Self.sameFolder(report.directory, folder)
                return Result(
                    application: app.name,
                    outcome: sameFolder ? .ran : .wrongFolder,
                    seconds: seconds,
                    accepted: accepted,
                    shell: report.shell,
                    detail: sameFolder ? nil : "The command ran in \(report.directory), not in the folder it was started in."
                )
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return Result(application: app.name, outcome: .noReply, accepted: accepted,
                      detail: "\(app.name) opened a session, but the typed command did not run within \(timeout).")
    }

    private static func read(_ marker: URL) -> (shell: String, directory: String)? {
        guard let text = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3, lines[2].isEmpty else { return nil }
        return (String(lines[0]), String(lines[1]))
    }

    private static func sameFolder(_ reported: String, _ expected: URL) -> Bool {
        URL(fileURLWithPath: reported).resolvingSymlinksInPath().path == expected.resolvingSymlinksInPath().path
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return ((Double(parts.seconds) + Double(parts.attoseconds) / 1e18) * 10).rounded() / 10
    }
}
