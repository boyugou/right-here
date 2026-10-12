import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

/// Finds the app bundle this `rh` belongs to: the one it sits inside, or else the installed app.
enum HostApp {
    static func locate(rhPath: String, facts: any SystemFacts) -> URL? {
        if let range = rhPath.range(of: ".app/Contents/") {
            return URL(fileURLWithPath: String(rhPath[..<range.lowerBound]) + ".app")
        }
        return facts.applicationURL(bundleID: AppIdentity.hostBundleID)
    }

    static func extensionURL(in app: URL) -> URL {
        app.appendingPathComponent("Contents/PlugIns/\(AppIdentity.extensionBundleName)")
    }
}

struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Connect Finder to rh.",
        discussion: """
        Without options everything is installed:

          --scripts   the runner script the Finder extension uses to reach rh
          --cli       a link to rh in ~/.local/bin
          --services  Finder Services (Quick Actions) for the actions in [services] of the config
          --finder    register and switch on the Finder extension of Right Here.app

        Nothing here needs administrator rights. Run it again at any time; it repairs what is out of date.
        With RH_HOME set, every per-user path (config, Services, runner script, command link) moves under that \
        folder, to try an install without touching your own.
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

    @Flag(name: .customLong("skip-finder"), help: "Install everything except the Finder extension.")
    var skipFinder = false

    func run() async throws {
        let runtime = Runtime()
        let everything = !(scripts || cli || services || finder)
        guard let rhPath = Installer.currentExecutablePath() else {
            throw Output.fail("error: cannot tell where rh is installed.")
        }
        if InstallError.isTranslocated(rhPath) { throw Output.fail("error: " + InstallError.translocated.localizedDescription) }
        let installer = Installer(home: runtime.facts.homeDirectory)

        // A step that fails does not stop the others: this is also the repair command.
        var problems = 0
        func attempt(_ label: String, _ body: () async throws -> Void) async {
            do { try await body() } catch {
                problems += 1
                Output.error("error: \(label): \(error.localizedDescription)")
            }
        }

        if everything || scripts {
            await attempt("runner script") { Output.print("Runner script: \(try installer.installRunnerScript(rhPath: rhPath).path)") }
        }
        if everything || cli {
            await attempt("command link") {
                let replaced = installer.existingCLILinkTarget().flatMap { $0 == rhPath ? nil : $0 }
                let link = try installer.installCLILink(rhPath: rhPath).path
                Output.print("Command link: \(link)" + (replaced.map { " (replaced a link to \($0))" } ?? ""))
            }
        }
        if everything {
            await attempt("config file") {
                let detected = await Detector(facts: runtime.facts).detect()
                if try ConfigStore.initialize(paths: runtime.paths, detected: detected) == .created {
                    Output.print("Config file: \(runtime.paths.configFile.path) (new)")
                }
            }
        }
        if everything || services {
            await attempt("Finder Services") {
                // The config may have been created a moment ago, so read it again: the Services follow what is in the file now.
                let config = ConfigStore.load(paths: runtime.paths).config
                let specs = ActionRegistry(config: config, facts: runtime.facts, localizer: .system).serviceSpecs(rhPath: rhPath)
                let written = try installer.installServices(specs)
                if ProcessInfo.processInfo.environment["RH_HOME"] == nil {
                    _ = try? await LiveProcessRunner().run(ProcessStep(executable: "/System/Library/CoreServices/pbs", arguments: ["-update"]), timeout: .seconds(20))
                }
                Output.print("Services: \(written.count) installed in \(installer.locations.services.path)")
            }
        }
        // The extension's registration is system-wide, not per home folder, so a trial under RH_HOME leaves it alone.
        let trialHome = ProcessInfo.processInfo.environment["RH_HOME"] != nil
        if finder || (everything && !skipFinder && !trialHome) {
            await attempt("Finder extension") {
                do {
                    try await installExtension(rhPath: rhPath, facts: runtime.facts)
                } catch InstallError.appNotFound where everything {
                    // A command-line-only install (Homebrew formula) has no app, and Quick Actions still work.
                    Output.print("Finder extension: skipped, Right Here.app is not installed. Quick Actions work without it.")
                }
            }
        }
        if problems > 0 {
            throw Output.fail("Finished with \(problems) problem(s). Run `rh doctor` to see what is still missing.")
        }
        Output.print("Done. Run `rh doctor` to check the setup.")
    }

    private func installExtension(rhPath: String, facts: any SystemFacts) async throws {
        guard let app = HostApp.locate(rhPath: rhPath, facts: facts) else { throw InstallError.appNotFound }
        let appex = HostApp.extensionURL(in: app).path
        guard FileManager.default.fileExists(atPath: appex) else { throw InstallError.extensionMissing(path: appex) }
        let manager = FinderExtensionManager()
        // A build folder or an old copy registered under the same identifier makes macOS drop the extension.
        for stale in await manager.status().paths where stale != appex {
            try? await manager.unregister(appexPath: stale)
            Output.print("Removed stale registration: \(stale)")
        }
        let registeredAgain = try await manager.registerAndConfirm(appexPath: appex)
        Output.print("Finder extension: \(appex) (enabled)" + (registeredAgain ? "; the first registration did not stay, so it was registered again" : ""))
    }
}

struct Uninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove what `rh install` set up. The config file is kept."
    )

    func run() async throws {
        let runtime = Runtime()
        let installer = Installer(home: runtime.facts.homeDirectory)
        try installer.removeRunnerScript()
        Output.print("Removed the runner script.")
        let services = installer.installedServices()
        if !services.isEmpty {
            try installer.removeServices()
            if ProcessInfo.processInfo.environment["RH_HOME"] == nil {
                _ = try? await LiveProcessRunner().run(ProcessStep(executable: "/System/Library/CoreServices/pbs", arguments: ["-update"]), timeout: .seconds(20))
            }
            Output.print("Removed \(services.count) Services.")
        }
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path) {
            if Installer.isRightHereBinary(destination) {
                try FileManager.default.removeItem(at: installer.cliLink)
                Output.print("Removed the command link (it pointed at \(destination)).")
            } else {
                // `rh` is a short name other tools use too; a link to something that is not Right Here's is not ours to delete.
                Output.print("Left the command link alone: \(installer.cliLink.path) points at \(destination), which is not Right Here's rh. Remove it yourself if you want it gone.")
            }
        }
        if ProcessInfo.processInfo.environment["RH_HOME"] != nil {
            Output.print("RH_HOME is set: the Finder extension's registration is system-wide and was left alone.")
            return
        }
        let manager = FinderExtensionManager()
        for path in await manager.status().paths {
            try? await manager.disable()
            try? await manager.unregister(appexPath: path)
            Output.print("Unregistered the Finder extension: \(path)")
        }
    }
}
