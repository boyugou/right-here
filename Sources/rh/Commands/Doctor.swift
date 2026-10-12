import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check that everything Right Here needs is in place.",
        discussion: "Each check has a status (ok, warn, fail, needs-user) and, when something is wrong, a fix. Exits with status 1 if any check fails."
    )

    @Flag(help: "Print JSON.")
    var json = false

    @Flag(help: "Also test the whole chain a Finder click uses, through the extension. Restarts the extension and may show a permission prompt.")
    var probeExtension = false

    @Flag(help: "Go further: have the extension start a throwaway terminal session that runs a typed command, as an agent launch does. A window opens and closes.")
    var probeLaunch = false

    @Option(help: "With --probe-launch: start the session in a \"window\" or a \"tab\" instead of what general.terminal_placement says.")
    var placement: String?

    struct Report: Encodable {
        var ok: Bool
        var checks: [DoctorCheck]
    }

    private func launchPlacement() throws -> TerminalPlacement? {
        guard let placement else { return nil }
        guard let parsed = TerminalPlacement(configName: placement) else { throw ValidationError("--placement is \"window\" or \"tab\".") }
        return parsed
    }

    func run() async throws {
        let runtime = Runtime()
        // A probe switches the Finder extension off and on again to make it look for its request. Ctrl-C in between
        // would leave it off (no menu until `rh install --finder`), so an interrupt switches it back on first.
        var interrupt: [DispatchSourceSignal] = []
        if probeExtension || probeLaunch {
            for number in [SIGINT, SIGTERM, SIGHUP] { signal(number, SIG_IGN) }
            let sources = [SIGINT, SIGTERM, SIGHUP].map { DispatchSource.makeSignalSource(signal: $0, queue: .global()) }
            for source in sources {
            source.setEventHandler {
                let reenable = Process()
                reenable.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
                reenable.arguments = ["-e", "use", "-i", AppIdentity.extensionBundleID]
                try? reenable.run()
                reenable.waitUntilExit()
                Darwin.exit(130)
            }
            source.resume()
            }
            interrupt = sources
        }
        defer { interrupt.forEach { $0.cancel() } }
        let checks = await RightHereKit.Doctor(paths: runtime.paths, loaded: runtime.loaded).run(probeExtension: probeExtension, probeLaunch: probeLaunch, launchPlacement: try launchPlacement())
        let failed = checks.contains { $0.status == .fail }
        if json {
            try Output.json(Report(ok: !failed, checks: checks))
        } else {
            for check in checks {
                Output.print("[\(check.status.rawValue)] \(check.title)" + (check.detail.map { ": \($0)" } ?? ""))
                if let fix = check.fix { Output.print("       fix: \(fix)") }
            }
        }
        if failed { throw ExitCode(1) }
    }
}
