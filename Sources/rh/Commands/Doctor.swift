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

    struct Report: Encodable {
        var ok: Bool
        var checks: [DoctorCheck]
    }

    func run() async throws {
        let runtime = Runtime()
        let checks = await RightHereKit.Doctor(paths: runtime.paths, loaded: runtime.loaded).run(probeExtension: probeExtension, probeLaunch: probeLaunch)
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
