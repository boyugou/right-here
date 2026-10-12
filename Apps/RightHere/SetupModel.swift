import AppKit
import FinderSync
import Observation
import RightHereCore
import RightHereKit

/// What the setup window shows and does. All the work is done by the same code `rh` uses.
@MainActor
@Observable
final class SetupModel {
    private(set) var checks: [DoctorCheck] = []
    private(set) var isWorking = false
    private(set) var message: String?

    private let facts = LiveSystemFacts()

    /// The `rh` that ships inside this app.
    private var helper: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/rh")
    }

    private var paths: RHPaths { RHPaths.current(facts: facts) }

    /// Whether any check is anything but ok, warnings included.
    var needsAttention: Bool {
        checks.contains { $0.status != .ok }
    }

    func refresh() async {
        isWorking = true
        defer { isWorking = false }
        let doctor = Doctor(facts: facts, paths: paths, loaded: ConfigStore.load(paths: paths), rhPath: helper.path)
        checks = await doctor.run()
    }

    /// Runs `rh install`: runner script, command link, config file and the Finder extension.
    func installOrRepair() async {
        isWorking = true
        message = nil
        do {
            let result = try await LiveProcessRunner().run(ProcessStep(executable: helper.path, arguments: ["install"]), timeout: .seconds(60))
            if result.status != 0 {
                let text = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                message = text.isEmpty ? "rh install exited with status \(result.status)" : text
            }
        } catch {
            // The system's own wording, in the system language; the install did not run to its end.
            message = error.localizedDescription
        }
        isWorking = false
        await refresh()
    }

    /// Has the Finder extension start a throwaway terminal session that runs a typed command, the
    /// way a menu click starts an agent, and shows what the doctor makes of it. A window opens and
    /// closes; the first time, macOS asks whether Right Here may control the terminal.
    func testTerminalLaunch() async {
        isWorking = true
        message = Localizer.system.string(.appTesting)
        let doctor = Doctor(facts: facts, paths: paths, loaded: ConfigStore.load(paths: paths), rhPath: helper.path)
        checks = await doctor.run(probeLaunch: true)
        message = nil
        isWorking = false
    }

    func showExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func openConfig() async {
        do {
            if !FileManager.default.fileExists(atPath: paths.configFile.path) {
                _ = try await LiveProcessRunner().run(ProcessStep(executable: helper.path, arguments: ["init"]), timeout: .seconds(30))
            }
            _ = try await LiveProcessRunner().run(ProcessStep(executable: "/usr/bin/open", arguments: ["-t", paths.configFile.path]))
        } catch {
            message = error.localizedDescription
        }
    }

    func copySetupPrompt() {
        let prompt = """
        Set up Right Here for me. Run `rh docs agent-setup` and follow it: run `rh doctor --json` and fix \
        whatever fails, then tailor ~/.config/right-here/config.toml to how I work, check it with \
        `rh config validate`, and show me the result with `rh menu`.
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        message = Localizer.system.string(.appPromptCopied)
    }
}
