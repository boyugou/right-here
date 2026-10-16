import Foundation
import RightHereCore
import Synchronization

/// Whether a launch probe is in the one stretch where the Finder extension is switched off and not yet on again. The probe restarts the extension with
/// `pluginkit -e ignore` and `-e use`; a process that ends between the two leaves Finder without its menu. The command line guards that with
/// `InterruptGuard`; the app does not quit while this says so (`applicationShouldTerminate`).
public final class ProbeActivity: Sendable {
    public static let shared = ProbeActivity()

    private let depth = Mutex(0)

    public init() {}

    public var isSwitching: Bool { depth.withLock { $0 > 0 } }

    func switching<Result: Sendable>(_ body: () async -> Result) async -> Result {
        depth.withLock { $0 += 1 }
        defer { depth.withLock { $0 -= 1 } }
        return await body()
    }
}

/// Asks the installed Finder extension to run a probe through the same chain a menu click uses
/// (extension, runner script, `rh`, then `osascript` or `open`), and reads the answer from the log.
///
/// The request is a marker file in the config folder; the extension looks for it when it starts
/// and runs `rh probe <kind> --from-extension`. The marker's text names the probe, so the extension
/// only ever runs a fixed command.
public struct ExtensionProbe: Sendable {
    public enum Kind: String, Sendable {
        /// Whether the extension may control the terminal (one harmless Apple event).
        case automation
        /// Whether a command typed into a new terminal session runs. Opens and closes a window.
        case launch
    }

    private let paths: RHPaths
    private let facts: any SystemFacts
    private let runner: any ProcessRunner
    private let activity: ProbeActivity
    private let environment: [String: String]

    public init(paths: RHPaths, facts: any SystemFacts = LiveSystemFacts(), runner: any ProcessRunner = LiveProcessRunner(), activity: ProbeActivity = .shared,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.paths = paths
        self.facts = facts
        self.runner = runner
        self.activity = activity
        self.environment = environment
    }

    private var logFile: URL { paths.logFile }

    /// Returns `nil` when nothing was reported in time.
    public func runAutomation(timeout: Duration = .seconds(45)) async -> [AutomationProbe.Result]? {
        guard let json = await report(.automation, timeout: timeout) else { return nil }
        return try? JSONDecoder().decode([AutomationProbe.Result].self, from: json)
    }

    /// Returns `nil` when nothing was reported in time. The time covers the permission prompt, the
    /// terminal starting and the person's shell starting up.
    /// - Parameter placement: `nil` tests what the config says; otherwise a window or a tab is forced.
    public func runLaunch(placement: TerminalPlacement? = nil, timeout: Duration = .seconds(75)) async -> LaunchProbe.Result? {
        guard let json = await report(.launch, marker: Self.markerText(placement: placement), timeout: timeout) else { return nil }
        return try? JSONDecoder().decode(LaunchProbe.Result.self, from: json)
    }

    /// The marker's text: `launch`, or `launch:window` / `launch:tab`. The extension accepts only these.
    static func markerText(placement: TerminalPlacement?) -> String {
        placement.map { "launch:" + $0.configName } ?? "launch"
    }

    /// Leaves the marker, restarts the extension so it looks for it, and waits for `rh` to report.
    private func report(_ kind: Kind, marker text: String? = nil, timeout: Duration) async -> Data? {
        let started = Date()
        // Restarting the extension is a change to the whole Mac (`RealHomeGuard`).
        guard (try? RealHomeGuard.checkSystemWide(environment: environment)) != nil else { return nil }
        guard ProbeMarker.write(text ?? kind.rawValue, in: paths) else { return nil }

        let manager = FinderExtensionManager(runner: runner, environment: environment)
        let runner = runner
        await activity.switching {
            try? await manager.disable()
            try? await Task.sleep(for: .seconds(1))
            _ = try? await runner.run(ProcessStep(executable: "/usr/bin/pluginkit", arguments: ["-e", "use", "-i", AppIdentity.extensionBundleID]), timeout: FinderExtensionManager.changeTimeout)
        }

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let json = Self.latestReport(kind, in: logFile, since: started) { return json }
            try? await Task.sleep(for: .milliseconds(500))
        }
        try? FileManager.default.removeItem(at: ProbeMarker.url(in: paths))
        return nil
    }

    /// The JSON of the most recent `probe <kind>` line logged after `date`.
    static func latestReport(_ kind: Kind, in log: URL, since date: Date) -> Data? {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return nil }
        let formatter = ISO8601DateFormatter()
        let prefix = "probe \(kind.rawValue): "
        for line in text.split(separator: "\n").reversed() {
            guard let space = line.firstIndex(of: " "), let when = formatter.date(from: String(line[..<space])),
                  when >= date.addingTimeInterval(-1) else { continue }
            let rest = line[line.index(after: space)...]
            guard rest.hasPrefix(prefix) else { continue }
            return Data(rest.dropFirst(prefix.count).utf8)
        }
        return nil
    }
}
