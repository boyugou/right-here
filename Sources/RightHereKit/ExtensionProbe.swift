import Foundation
import RightHereCore

/// Asks the installed Finder extension to run an automation probe through the same chain a menu
/// click uses (extension, runner script, `rh`, `osascript`), and reads the answer from the log.
public struct ExtensionProbe: Sendable {
    private let paths: RHPaths
    private let facts: any SystemFacts
    private let runner: any ProcessRunner

    public init(paths: RHPaths, facts: any SystemFacts = LiveSystemFacts(), runner: any ProcessRunner = LiveProcessRunner()) {
        self.paths = paths
        self.facts = facts
        self.runner = runner
    }

    private var logFile: URL {
        facts.homeDirectory.appendingPathComponent("Library/Logs/right-here/rh.log")
    }

    /// Leaves the marker, restarts the extension so it looks for it, and waits for `rh` to report.
    /// Returns `nil` when nothing was reported in time.
    public func run(timeout: Duration = .seconds(45)) async -> [AutomationProbe.Result]? {
        let started = Date()
        let marker = paths.configDirectory.appendingPathComponent(".probe")
        try? FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        guard (try? Data().write(to: marker)) != nil else { return nil }

        let manager = FinderExtensionManager(runner: runner)
        try? await manager.disable()
        try? await Task.sleep(for: .seconds(1))
        _ = try? await runner.run(ProcessStep(executable: "/usr/bin/pluginkit", arguments: ["-e", "use", "-i", AppIdentity.extensionBundleID]))

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let results = Self.latestResults(in: logFile, since: started) { return results }
            try? await Task.sleep(for: .milliseconds(500))
        }
        try? FileManager.default.removeItem(at: marker)
        return nil
    }

    /// The most recent `probe automation` line logged after `date`.
    static func latestResults(in log: URL, since date: Date) -> [AutomationProbe.Result]? {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return nil }
        let formatter = ISO8601DateFormatter()
        for line in text.split(separator: "\n").reversed() {
            guard let space = line.firstIndex(of: " "), let when = formatter.date(from: String(line[..<space])),
                  when >= date.addingTimeInterval(-1) else { continue }
            let rest = line[line.index(after: space)...]
            guard rest.hasPrefix("probe automation: ") else { continue }
            let json = rest.dropFirst("probe automation: ".count)
            return try? JSONDecoder().decode([AutomationProbe.Result].self, from: Data(json.utf8))
        }
        return nil
    }
}
