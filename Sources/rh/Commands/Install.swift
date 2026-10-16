import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Put one piece of the Finder connection in place again.",
        discussion: """
        `rh setup` does all of this and more, in order, and can be run again at any time. Use this command to redo exactly one piece:

          --scripts   the runner script the Finder extension uses to reach rh
          --cli       a link to rh in ~/.local/bin
          --services  Finder Services (Quick Actions) from [services] in the config
          --finder    register and switch on the Finder extension of Right Here.app

        Name at least one. Nothing here needs administrator rights, and each piece compares before it writes, so running it again \
        changes only what is out of date. With RH_HOME set, every per-user path (config, Services, runner script, command link) \
        moves under that folder, to try an install without touching your own; --finder still registers the extension for the \
        whole Mac, because you asked for it by name.
        """
    )

    @Flag(help: "Install only the runner script.")
    var scripts = false

    @Flag(help: "Install only the command-line link.")
    var cli = false

    @Flag(help: "Install only the Finder Services (Quick Actions).")
    var services = false

    @Flag(help: "Register and switch on only the Finder extension.")
    var finder = false

    func run() async throws {
        var pieces: Set<SetupPiece> = []
        if scripts { pieces.insert(.runnerScript) }
        if cli { pieces.insert(.cliLink) }
        if services { pieces.insert(.services) }
        if finder { pieces.insert(.finderExtension) }
        guard !pieces.isEmpty else {
            throw ValidationError("Name what to install: --scripts, --cli, --services or --finder. To do everything, run `rh setup`.")
        }
        // The extension's registration is for the whole Mac, which a trial under RH_HOME leaves alone unless it was asked for by name.
        let runner = try SetupCommandSupport.runner(systemWide: finder ? true : nil)
        let report = try await SetupCommandSupport.run(SetupRequest(pieces: pieces, strict: true), with: runner)
        try SetupCommandSupport.finish(report, json: false, withTitle: false)
    }
}

struct Uninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove what `rh setup` set up. The config file is kept."
    )

    func run() async throws {
        let runtime = Runtime()
        let installer = Installer(home: runtime.facts.homeDirectory)
        // As in `setup`, a step that fails does not stop the others: what is left behind is reported at the end.
        var problems = 0
        func attempt(_ label: String, _ body: () async throws -> Void) async {
            do { try await body() } catch {
                problems += 1
                Output.error("error: \(label): \(error.localizedDescription)")
            }
        }
        await attempt("runner script") {
            let existed = FileManager.default.fileExists(atPath: installer.runnerScript.path)
            try installer.removeRunnerScript()
            if existed { Output.print("Removed the runner script.") }
        }
        await attempt("Services") {
            let services = installer.installedServices()
            guard !services.isEmpty else { return }
            try installer.removeServices()
            if ProcessInfo.processInfo.environment["RH_HOME"] == nil {
                _ = try? await LiveProcessRunner().run(ProcessStep(executable: "/System/Library/CoreServices/pbs", arguments: ["-update"]), timeout: .seconds(20))
            }
            Output.print("Removed \(services.count) Services.")
        }
        await attempt("command link") {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path) else { return }
            if Installer.isRightHereBinary(destination) {
                try FileManager.default.removeItem(at: installer.cliLink)
                Output.print("Removed the command link (it pointed at \(destination.withControlCharactersEscaped)).")
            } else {
                // `rh` is a short name other tools use too; a link to something that is not Right Here's is not ours to delete.
                Output.print("Left the command link alone: \(installer.cliLink.path.withControlCharactersEscaped) points at \(destination.withControlCharactersEscaped), which is not Right Here's rh. Remove it yourself if you want it gone.")
            }
        }
        if ProcessInfo.processInfo.environment["RH_HOME"] != nil {
            Output.print("RH_HOME is set: the Finder extension's registration is system-wide and was left alone.")
            if problems > 0 { throw Output.fail("\(problems) step(s) failed; run `rh uninstall` again once the cause is fixed.") }
            return
        }
        let manager = FinderExtensionManager()
        for path in await manager.status().paths {
            try? await manager.disable()
            try? await manager.unregister(appexPath: path)
            Output.print("Unregistered the Finder extension: \(path.withControlCharactersEscaped)")
        }
        if problems > 0 { throw Output.fail("\(problems) step(s) failed; run `rh uninstall` again once the cause is fixed.") }
    }
}
