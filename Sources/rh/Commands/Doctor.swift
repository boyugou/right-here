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

    @Option(help: "With --probe-launch: start the session in a \"window\", \"tab\", \"split-right\" or \"split-down\" instead of what general.terminal_placement says.")
    var placement: String?

    struct Report: Encodable {
        var ok: Bool
        var checks: [DoctorCheck]
    }

    private func launchPlacement() throws -> TerminalPlacement? {
        guard let placement else { return nil }
        guard let parsed = TerminalPlacement(configName: placement) else {
            throw ValidationError("--placement must be one of: \(TerminalPlacement.configNames.joined(separator: ", ")).")
        }
        return parsed
    }

    func run() async throws {
        let runtime = Runtime()
        // The rows mix this home (config, log, runner script, Services, command link) with what is registered system-wide (the
        // extension), so a trial home says so. On standard error: `--json` keeps standard output a document.
        if let home = LiveSystemFacts.homeOverride {
            Output.error("note: RH_HOME is set, so the config, run log, runner script, Services and command link are looked for under \(home.path), not in your home folder. The Finder extension is checked as it is really registered.")
        }
        // A probe switches the Finder extension off and on again to make it look for its request. Ctrl-C in between
        // would leave it off (no menu until `rh setup`), so an interrupt switches it back on first.
        let paths = runtime.paths
        let interrupt = (probeExtension || probeLaunch) ? InterruptGuard(paths: paths, reenableExtension: {
            let reenable = Process()
            reenable.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            reenable.arguments = ["-e", "use", "-i", AppIdentity.extensionBundleID]
            try? reenable.run()
            reenable.waitUntilExit()
        }, finish: { Darwin.exit(130) }) : nil
        defer { interrupt?.cancel() }
        let checks = await RightHereKit.Doctor(paths: runtime.paths, loaded: runtime.loaded).run(probeExtension: probeExtension, probeLaunch: probeLaunch, launchPlacement: try launchPlacement())
        let failed = checks.contains { $0.status == .fail }
        if json {
            try Output.json(Report(ok: !failed, checks: checks))
        } else {
            for line in checks.flatMap({ $0.englishLines() }) { Output.print(line) }
        }
        if failed { throw ExitCode(1) }
    }
}
