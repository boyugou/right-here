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

          --scripts  the runner script the Finder extension uses to reach rh
          --cli      a link to rh in ~/.local/bin
          --finder   register and switch on the Finder extension of Right Here.app

        Nothing here needs administrator rights. Run it again at any time; it repairs what is out of date.
        """
    )

    @Flag(help: "Install only the runner script.")
    var scripts = false

    @Flag(help: "Install only the command-line link.")
    var cli = false

    @Flag(help: "Register and switch on only the Finder extension.")
    var finder = false

    func run() async throws {
        let runtime = Runtime()
        let everything = !(scripts || cli || finder)
        guard let rhPath = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
            throw Output.fail("error: cannot tell where rh is installed.")
        }
        let installer = Installer(home: runtime.facts.homeDirectory)

        if everything || scripts {
            Output.print("Runner script: \(try installer.installRunnerScript(rhPath: rhPath).path)")
        }
        if everything || cli {
            Output.print("Command link: \(try installer.installCLILink(rhPath: rhPath).path)")
        }
        if everything {
            let detected = await Detector(facts: runtime.facts).detect()
            if try ConfigStore.initialize(paths: runtime.paths, detected: detected) {
                Output.print("Config file: \(runtime.paths.configFile.path) (new)")
            }
        }
        if everything || finder {
            try await installExtension(rhPath: rhPath, facts: runtime.facts)
        }
        Output.print("Done. Run `rh doctor` to check the setup.")
    }

    private func installExtension(rhPath: String, facts: any SystemFacts) async throws {
        guard let app = HostApp.locate(rhPath: rhPath, facts: facts) else {
            throw Output.fail("error: Right Here.app was not found. Install the app, then run `rh install --finder`.")
        }
        let appex = HostApp.extensionURL(in: app).path
        guard FileManager.default.fileExists(atPath: appex) else {
            throw Output.fail("error: \(appex) does not exist.")
        }
        let manager = FinderExtensionManager()
        // A build folder or an old copy registered under the same identifier makes macOS drop the extension.
        for stale in await manager.status().paths where stale != appex {
            try? await manager.unregister(appexPath: stale)
            Output.print("Removed stale registration: \(stale)")
        }
        try await manager.register(appexPath: appex)
        Output.print("Finder extension: \(appex) (enabled)")
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
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path) {
            try FileManager.default.removeItem(at: installer.cliLink)
            Output.print("Removed the command link (it pointed at \(destination)).")
        }
        let manager = FinderExtensionManager()
        for path in await manager.status().paths {
            try? await manager.disable()
            try? await manager.unregister(appexPath: path)
            Output.print("Unregistered the Finder extension: \(path)")
        }
    }
}
