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

    /// The Finder extension is the one thing the first-run card waits for.
    var extensionNeedsSetup: Bool {
        checks.contains { $0.id == .finderExtension && $0.status != .ok }
    }

    /// Whether the details list starts open: when something needs attention, except under the first-run card.
    var detailsStartOpen: Bool {
        #if PREVIEW
        if previewOpensDetails { return true }
        #endif
        return needsAttention && !extensionNeedsSetup
    }

    #if PREVIEW
    private var simulated = false
    private var previewOpensDetails = false

    /// For `script/preview_setup.sh --onboarding`: shows the first-run card on a machine where the extension is on.
    func simulateExtensionOff() {
        checks = checks.map { check in
            var copy = check
            if check.id == .finderExtension { copy.status = .needsUser }
            return copy
        }
    }

    /// For `script/preview_setup.sh --demo` and `--gallery`: shows these checks and nothing this machine says, now or
    /// later: a refresh is ignored from here on.
    func simulate(checks: [DoctorCheck], opensDetails: Bool = false) {
        self.checks = checks
        simulated = true
        previewOpensDetails = opensDetails
    }
    #endif

    func check(_ id: CheckID) -> DoctorCheck? {
        checks.first { $0.id == id }
    }

    /// While the extension is not switched on, looks at it every two seconds, so the card turns green by itself
    /// after the person flips the switch in System Settings. A look is the extension's check alone (one `pluginkit`
    /// call), not the whole doctor; when the extension is on, one full refresh follows. It stops as soon as the
    /// extension is ok, and when the caller's task is cancelled (the window closed). It stays out of the way of work
    /// the person started.
    func watchExtension() async {
        while extensionNeedsSetup, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            if !isWorking, !Task.isCancelled, await refreshExtension() { await refresh(quiet: true) }
        }
    }

    /// Looks at the Finder extension alone and puts the answer in the extension's place in `checks`.
    /// - Returns: whether the extension is ok.
    private func refreshExtension() async -> Bool {
        #if PREVIEW
        if simulated { return false }
        #endif
        let check = await Doctor.extensionCheck(runner: LiveProcessRunner())
        // Work the person started meanwhile ends in a full refresh of its own, which is newer than this look; and a
        // look that was cut short by the window closing says nothing.
        guard !isWorking, !Task.isCancelled else { return false }
        checks = checks.replacing(check)
        return check.status == .ok
    }

    /// - Parameter quiet: Do not show the busy state (buttons stay enabled); used by the refresh after a background look.
    func refresh(quiet: Bool = false) async {
        #if PREVIEW
        if simulated { return }
        #endif
        if !quiet { isWorking = true }
        defer { if !quiet { isWorking = false } }
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
                let created = try await LiveProcessRunner().run(ProcessStep(executable: helper.path, arguments: ["init"]), timeout: .seconds(30))
                if created.status != 0 {
                    let text = created.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    message = text.isEmpty ? "rh init exited with status \(created.status)" : text
                    return
                }
            }
            let opened = try await LiveProcessRunner().run(ProcessStep(executable: "/usr/bin/open", arguments: ["-t", paths.configFile.path]))
            if opened.status != 0 {
                let text = opened.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                message = text.isEmpty ? "open exited with status \(opened.status)" : text
            }
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
