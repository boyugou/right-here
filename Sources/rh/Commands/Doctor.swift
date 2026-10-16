import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check that everything Right Here needs is in place.",
        discussion: "Each check has a status (ok, warn, fail, needs-user) and, when something is wrong, a fix. Exits with status 1 if any check fails."
    )

    @Flag(help: "Print JSON, for you and your AI agent. It holds the names, commands and paths from your config as they are, so it is not for a public issue: --report is.")
    var json = false

    @Flag(help: "Print a report for a public bug report, as Markdown: the versions of rh and the app, macOS and the processor, the checks in Right Here's own words, and the counts of the config check. What your config says (names, commands, folders, the text of its errors) is left out and shown as …; the home folder is shown as ~ and the account name is removed.")
    var report = false

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
        if report, json { throw ValidationError("--report and --json cannot be combined: the report is Markdown.") }
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
        if report {
            Output.print(DoctorReport.markdown(identity: identity(runtime), configCheck: configCheck(runtime), checks: checks, privacy: privacy(runtime)))
        } else if json {
            try Output.json(Report(ok: !failed, checks: checks))
        } else {
            for line in checks.flatMap({ $0.englishLines() }) { Output.print(line) }
        }
        if failed { throw ExitCode(1) }
    }

    private func identity(_ runtime: Runtime) -> DoctorReport.Identity {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DoctorReport.Identity(
            rhVersion: AppIdentity.version,
            appVersion: runtime.facts.bundleVersion(bundleID: AppIdentity.hostBundleID),
            macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            architecture: Self.architecture()
        )
    }

    static func architecture() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: system.machine) { raw in String(cString: raw.bindMemory(to: CChar.self).baseAddress!) }
    }

    /// The home folders that may appear in the report, and the account name: the real ones, and the trial home `RH_HOME` names.
    private func privacy(_ runtime: Runtime) -> DoctorReport.Privacy {
        var homes = [runtime.facts.homeDirectory.path]
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir { homes.append(String(cString: directory)) }
        if let override = LiveSystemFacts.homeOverride { homes.append(override.path) }
        let account = getpwuid(getuid()).flatMap { $0.pointee.pw_name }.map { String(cString: $0) } ?? NSUserName()
        return DoctorReport.Privacy(homes: homes, account: account)
    }

    /// The result line of `rh config validate --strict`: counts, because the diagnostics quote the config.
    private func configCheck(_ runtime: Runtime) -> String {
        let loaded = ConfigStore.load(paths: runtime.paths, validating: true)
        guard loaded.fileExists || loaded.localFileExists else { return "no config file" }
        let result = loaded.resultWithMenuCheck(facts: runtime.facts)
        if result.diagnostics.isEmpty { return "ok" }
        let errors = result.diagnostics.filter { $0.severity == .error }.count
        let warnings = result.diagnostics.count - errors
        return "\(errors) error\(errors == 1 ? "" : "s"), \(warnings) warning\(warnings == 1 ? "" : "s")"
    }
}
