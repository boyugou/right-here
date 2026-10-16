import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct Probe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check what this context is allowed to do.",
        subcommands: [Automation.self, Launch.self]
    )

    /// The Finder extension asks for a probe by leaving `.probe` in the config folder. Several
    /// extension processes can start at once (Finder and every Open panel) and all see it, so only
    /// the one whose `rename` takes the file runs the probe, and only while the request is fresh.
    static func claimMarker(paths: RHPaths) -> Bool {
        ProbeMarker.claim(in: paths)
    }

    static func record(_ name: String, _ value: some Encodable) {
        let json = (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        RunLog.record("probe \(name): " + json)
    }

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

        @Flag(name: .customLong("from-extension"), help: .hidden)
        var fromExtension = false

        func run() async throws {
            let runtime = Runtime()
            if fromExtension, !Probe.claimMarker(paths: runtime.paths) { return }

            var targets: [AppDescriptor] = []
            if apps.isEmpty {
                if let terminal = try? runtime.defaults.resolve(role: .terminal, configured: runtime.config.terminal) { targets = [terminal] }
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
            if log || fromExtension { Probe.record("automation", results) }
            if json {
                try Output.json(results)
            } else {
                for result in results {
                    Output.print("\(result.application.withControlCharactersEscaped): \(result.outcome.rawValue)" + (result.detail.map { " (\($0.withControlCharactersEscaped))" } ?? ""))
                }
            }
            if results.contains(where: { $0.outcome == .denied || $0.outcome == .failed }) { throw ExitCode(1) }
        }
    }

    struct Launch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Start a throwaway terminal session that runs a typed command, and check that it ran.",
            discussion: """
            Opens a session in a scratch folder (its name has spaces and quotes on purpose), types a \
            command that writes a file and exits, and waits for the file. That shows the terminal \
            accepts a typed command, presses Return, starts in the right folder and runs your login \
            shell, which is what starting an agent needs. The window closes itself and shows briefly.

            The result describes whoever ran this command: from the Finder extension's runner \
            (`rh doctor --probe-launch`) it describes what a menu click can do.
            """
        )

        @Argument(help: "A terminal id from `rh apps`. Default: the default terminal.")
        var terminal: String?

        @Option(help: "Start the session in a new \"window\", \"tab\", \"split-right\" or \"split-down\". Default: general.terminal_placement.")
        var placement: String?

        @Flag(help: "Print JSON.")
        var json = false

        @Flag(help: "Record the result in the log, for diagnosis of the Finder extension.")
        var log = false

        @Flag(name: .customLong("from-extension"), help: .hidden)
        var fromExtension = false

        func run() async throws {
            let runtime = Runtime()
            if fromExtension, !Probe.claimMarker(paths: runtime.paths) { return }

            let result = try await probe(runtime)
            if log || fromExtension { Probe.record("launch", result) }
            if json {
                try Output.json(result)
            } else {
                var line = "\(result.application.withControlCharactersEscaped): \(result.outcome.rawValue)"
                if let seconds = result.seconds { line += String(format: " in %.1f s", seconds) }
                if let accepted = result.accepted { line += String(format: " (request accepted after %.1f s)", accepted) }
                if let shell = result.shell { line += ", login shell \(shell.withControlCharactersEscaped)" }
                if let detail = result.detail { line += " (\(detail.withControlCharactersEscaped))" }
                Output.print(line)
            }
            if result.outcome != .ran { throw ExitCode(1) }
        }

        private func probe(_ runtime: Runtime) async throws -> LaunchProbe.Result {
            // Arguments are checked before anything is looked up or started.
            var chosen = runtime.config.terminalPlacement
            if let placement {
                guard let parsed = TerminalPlacement(configName: placement) else {
                    throw ValidationError("--placement must be one of: \(TerminalPlacement.configNames.joined(separator: ", ")).")
                }
                chosen = parsed
            }
            let app: AppDescriptor
            if let terminal {
                guard let found = runtime.config.app(id: terminal), found.role == .terminal else {
                    throw ValidationError("Unknown terminal \"\(terminal)\". Run `rh apps`.")
                }
                app = found
            } else {
                do {
                    app = try runtime.defaults.resolve(role: .terminal, configured: runtime.config.terminal)
                } catch {
                    return .init(application: "terminal", outcome: .notInstalled, detail: error.localizedDescription)
                }
            }
            guard let bundleID = app.installedBundleID(facts: runtime.facts) else {
                return .init(application: app.name, outcome: .notInstalled, detail: "\(app.name) is not installed.")
            }
            return await LaunchProbe(facts: runtime.facts).run(terminal: app, bundleID: bundleID, placement: chosen)
        }
    }
}
