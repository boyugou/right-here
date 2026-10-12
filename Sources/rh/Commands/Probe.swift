import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct Probe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check what this context is allowed to do.",
        subcommands: [Automation.self]
    )

    struct Automation: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check whether this context may control the terminal (or other apps) through Apple events.",
            discussion: """
            Sends one harmless Apple event (`get name`) to each app. macOS asks the person to allow it the \
            first time. The result describes whoever ran this command: from the Finder extension's runner \
            it describes the extension, from a terminal it describes that terminal. Apps that are not \
            running are reported, not started.
            """
        )

        @Argument(help: "App ids from `rh apps`. Default: the default terminal.")
        var apps: [String] = []

        @Flag(help: "Print JSON.")
        var json = false

        @Flag(help: "Record the result in the log, for diagnosis of the Finder extension.")
        var log = false

        func run() async throws {
            let runtime = Runtime()
            // The Finder extension starts a probe by leaving this file behind; remove it so it runs once.
            try? FileManager.default.removeItem(at: runtime.paths.configDirectory.appendingPathComponent(".probe"))

            var targets: [AppDescriptor] = []
            if apps.isEmpty {
                if let terminal = try? runtime.planner.resolveDefault(role: .terminal, configured: runtime.config.terminal) { targets = [terminal] }
            } else {
                for id in apps {
                    guard let app = runtime.config.app(id: id) else { throw ValidationError("Unknown app \"\(id)\". Run `rh apps`.") }
                    targets.append(app)
                }
            }
            let probe = AutomationProbe(facts: runtime.facts)
            var results: [AutomationProbe.Result] = []
            for app in targets {
                guard let bundleID = app.installedBundleID(facts: runtime.facts) else {
                    results.append(.init(application: app.name, bundleID: app.bundleIDs.first ?? "", outcome: .failed, detail: "\(app.name) is not installed."))
                    continue
                }
                results.append(await probe.check(name: app.name, bundleID: bundleID))
            }
            if log {
                let line = (try? JSONEncoder().encode(results)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
                RunLog.record("probe automation: " + line)
            }
            if json {
                try Output.json(results)
            } else {
                for result in results {
                    Output.print("\(result.application): \(result.outcome.rawValue)" + (result.detail.map { " (\($0))" } ?? ""))
                }
            }
            if results.contains(where: { $0.outcome == .denied || $0.outcome == .failed }) { throw ExitCode(1) }
        }
    }
}
