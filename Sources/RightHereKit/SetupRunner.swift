import Foundation
import RightHereCore

/// What to put in place: which pieces, with what choices.
public struct SetupRequest: Sendable, Equatable {
    public var pieces: Set<SetupPiece>
    /// What the person said they use. It only counts when the config is created (or replaced, with `force`).
    public var choices: SetupChoices
    /// Replace a config that exists, after saving it next to itself.
    public var force: Bool
    /// Work out what would be done, and write nothing and start nothing that changes anything.
    public var dryRun: Bool
    /// Run the doctor at the end and say what is left for the person.
    public var checkup: Bool
    /// A piece that cannot be done is a failure (a command of its own, `rh install --finder`) and not a skip (setup as a whole).
    public var strict: Bool

    public init(pieces: Set<SetupPiece>, choices: SetupChoices = SetupChoices(), force: Bool = false, dryRun: Bool = false, checkup: Bool = false, strict: Bool = false) {
        self.pieces = pieces
        self.choices = choices
        self.force = force
        self.dryRun = dryRun
        self.checkup = checkup
        self.strict = strict
    }

    /// `rh setup`, and the setup window: every piece, then the doctor.
    public static func setup(choices: SetupChoices = SetupChoices(), force: Bool = false, dryRun: Bool = false) -> SetupRequest {
        SetupRequest(pieces: Set(SetupPiece.allCases), choices: choices, force: force, dryRun: dryRun, checkup: true, strict: false)
    }

    /// The command line that asks for the same, as `rh setup` takes it.
    var englishCommand: String {
        var words = ["rh", "setup"]
        if let terminal = choices.terminal { words += ["--terminal", terminal] }
        if let editor = choices.editor { words += ["--editor", editor] }
        if let agents = choices.agents { words += ["--agents", agents.isEmpty ? SetupChoices.noAgents : agents.joined(separator: ",")] }
        if force { words.append("--force") }
        return words.joined(separator: " ")
    }
}

/// Puts Right Here in place for a person, in order, and says what it did: the config (created from what is installed and what the
/// person says, never rewritten when it exists), the runner script, the command link, the Quick Actions and the Finder extension's
/// registration, then the doctor. Every piece compares before it writes, so a second run does nothing and says so.
///
/// It is the one implementation behind `rh setup`, `rh init`, `rh install` and the setup window. It opens no window and starts no
/// terminal, it never touches System Settings, and what it changes for the whole Mac (the extension's registration, the Services
/// cache) it changes only when `systemWide` says so: a trial under `RH_HOME` leaves that alone.
public struct SetupRunner: Sendable {
    private let facts: any SystemFacts
    private let paths: RHPaths
    private let runner: any ProcessRunner
    private let rhPath: String
    private let app: URL?
    private let trialHome: URL?
    private let systemWide: Bool
    private let localizer: Localizer
    private let settle: Duration

    /// - Parameters:
    ///   - rhPath: The `rh` that the runner script and the Quick Actions run: the one inside Right Here.app for the app, the running
    ///     one for the command line.
    ///   - app: The Right Here.app that has the Finder extension: the one that holds `rhPath`, or the installed one; `nil` when there is none.
    ///   - trialHome: The folder `RH_HOME` names, when it is set.
    ///   - systemWide: Whether what is registered for the whole Mac may be changed. By default, when there is no trial home.
    public init(facts: any SystemFacts = LiveSystemFacts(), paths: RHPaths? = nil, runner: any ProcessRunner = LiveProcessRunner(), rhPath: String, app: URL?,
                trialHome: URL? = LiveSystemFacts.homeOverride, systemWide: Bool? = nil, localizer: Localizer = .system, settle: Duration = .seconds(3)) {
        self.facts = facts
        self.paths = paths ?? RHPaths.current(facts: facts)
        self.runner = runner
        self.rhPath = rhPath
        self.app = app
        self.trialHome = trialHome
        self.systemWide = systemWide ?? (trialHome == nil)
        self.localizer = localizer
        self.settle = settle
    }

    public func run(_ request: SetupRequest) async throws -> SetupReport {
        // The runner script and the Services would point into a folder that disappears when the app quits.
        if InstallError.isTranslocated(rhPath) { throw InstallError.translocated }
        let installer = Installer(home: facts.homeDirectory)
        var report = SetupReport(dryRun: request.dryRun, trialHome: trialHome?.path)

        // What a dry run would have written: the Quick Actions of the plan are counted from it, not from a file that is not there yet.
        var planned: Config?
        for piece in SetupPiece.allCases where request.pieces.contains(piece) {
            switch piece {
            case .config: planned = await configStep(request, into: &report)
            case .runnerScript: report.steps.append(runnerScriptStep(installer, dryRun: request.dryRun))
            case .cliLink: report.steps.append(cliLinkStep(installer, dryRun: request.dryRun))
            case .services: report.steps.append(await servicesStep(installer, dryRun: request.dryRun, planned: planned))
            case .finderExtension: report.steps.append(await finderExtensionStep(strict: request.strict, dryRun: request.dryRun))
            }
        }

        let loaded = ConfigStore.load(paths: paths)
        if request.checkup, !request.dryRun {
            var rows = await Doctor(facts: facts, paths: paths, loaded: loaded, runner: runner, rhPath: rhPath).run()
            // What a trial says about the Finder extension is what this Mac says, not what the trial did.
            if !systemWide { rows.removeAll { $0.id == .finderExtension } }
            report.checks = rows
            report.needsUser = SetupAdvice.needsUser(checks: rows, config: loaded.config, facts: facts)
        }
        report.warnings += notes(editsPending: !report.configEdits.isEmpty)
        report.next = request.checkup ? SetupAdvice.next(configEdits: report.configEdits, needs: report.needsUser, checked: !request.dryRun,
                                                         rerun: request.dryRun ? request.englishCommand : nil) : []
        return report
    }

    // MARK: Notes

    private func notes(editsPending: Bool) -> [String] {
        var notes: [String] = []
        if let trialHome, !systemWide {
            notes.append("RH_HOME is set, so this is a trial: the config, the runner script, the command link and the Quick Actions are under \(trialHome.path), and the Finder extension, which is registered for the whole Mac, was neither changed nor checked.")
        }
        if systemWide, HostApp.isBuildProduct(rhPath) {
            notes.append("This rh runs from a build folder (\(rhPath)), and the runner script and the Quick Actions now point at it: they stop working when that folder is cleaned. For a lasting setup run the rh inside Right Here.app (Right Here.app/Contents/Helpers/rh setup).")
        }
        if editsPending {
            notes.append("\(paths.configFile.lastPathComponent) already exists, so Right Here left it alone and did not apply your choices. The edits that would make it say so are listed above (and in configEdits with --json).")
        }
        return notes
    }

    // MARK: Pieces

    private func entryExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// - Returns: In a dry run that would write a config, the config it would write; otherwise `nil`, and what depends on the config reads the file.
    private func configStep(_ request: SetupRequest, into report: inout SetupReport) async -> Config? {
        let exists = entryExists(paths.configFile)
        if exists, !request.force {
            let loaded = ConfigStore.load(paths: paths)
            if let problem = loaded.fileProblem {
                report.steps.append(SetupStep(.config, .unchanged, detail: .doctorVerbatim("\(paths.configFile.path) already exists but was not read (\(problem.message)); kept it as it is")))
            } else {
                report.steps.append(SetupStep(.config, .unchanged, detail: .doctorVerbatim("\(paths.configFile.path); it is yours, so setup never rewrites it")))
            }
            if !request.choices.isEmpty {
                func text(_ file: URL) -> String? {
                    if case .text(let text) = ConfigStore.text(of: file) { return text }
                    return nil
                }
                report.configEdits = ConfigEdits.needed(for: request.choices, config: loaded.config, base: text(paths.configFile), local: text(paths.localConfigFile),
                                                        baseName: paths.configFile.lastPathComponent, localName: paths.localConfigFile.lastPathComponent)
            }
            return nil
        }

        var detected = DetectedEnvironment()
        let choices = request.choices
        if choices.terminal == nil || choices.editor == nil || choices.agents == nil {
            detected = await Detector(facts: facts, runner: runner).detect()
        }
        let written = detected.applying(choices)
        report.chosen = chosen(written, choices: choices)
        if let warning = SetupChoices.agentTerminalWarning(terminal: written.terminal, agents: written.agents) { report.warnings.append(warning) }
        if request.dryRun {
            report.steps.append(SetupStep(.config, exists ? .updated : .created, detail: .doctorVerbatim(paths.configFile.path + (exists ? "; the old file would be saved next to it first" : ""))))
            return plannedConfig(written)
        }
        do {
            switch try ConfigStore.initialize(paths: paths, detected: written, force: request.force) {
            case .created:
                report.steps.append(SetupStep(.config, .created, detail: .doctorVerbatim(paths.configFile.path)))
            case .replaced(let backup):
                report.steps.append(SetupStep(.config, .updated, detail: .doctorVerbatim("\(paths.configFile.path); the old file is saved as \(backup.path)")))
            case .kept:
                // A config appeared between the check and the write (the setup window, or another terminal): it is the one that stays.
                report.steps.append(SetupStep(.config, .unchanged, detail: .doctorVerbatim("\(paths.configFile.path) was made a moment ago by something else: it is kept")))
                report.chosen = nil
            }
        } catch {
            report.steps.append(SetupStep(.config, .failed, detail: .doctorVerbatim(error.localizedDescription)))
            report.chosen = nil
        }
        return nil
    }

    /// The config that a run with these choices would create, with the per-machine overlay on top as it is read now.
    private func plannedConfig(_ written: DetectedEnvironment) -> Config {
        let local: ConfigSource
        switch ConfigStore.text(of: paths.localConfigFile) {
        case .absent: local = .absent
        case .text(let text): local = .text(text)
        case .problem(let message): local = .unreadable(ConfigDiagnostic(severity: .error, path: "", message: message))
        }
        return ConfigLayers.load(base: .text(ConfigTemplate.render(written)), local: local, overlayName: paths.localConfigFile.lastPathComponent).config
    }

    private func chosen(_ written: DetectedEnvironment, choices: SetupChoices) -> SetupReport.Chosen {
        func pick(_ id: String, name: String?, said: Bool) -> SetupReport.Pick {
            SetupReport.Pick(id: id, name: name ?? id, source: said ? .you : .found)
        }
        return SetupReport.Chosen(
            terminal: written.terminal.map { pick($0, name: KnownApps.app(id: $0)?.name, said: choices.terminal != nil) },
            editor: written.editor.map { pick($0, name: KnownApps.app(id: $0)?.name, said: choices.editor != nil) },
            agents: written.agents.map { pick($0, name: KnownAgents.agent(id: $0)?.name, said: choices.agents != nil) })
    }

    private func runnerScriptStep(_ installer: Installer, dryRun: Bool) -> SetupStep {
        let detail = LocalizedMessage.doctorVerbatim(installer.runnerScript.path)
        if installer.runnerScriptIsCurrent(rhPath: rhPath) { return SetupStep(.runnerScript, .unchanged, detail: detail) }
        let outcome: SetupStep.Outcome = entryExists(installer.runnerScript) ? .updated : .created
        if dryRun { return SetupStep(.runnerScript, outcome, detail: detail) }
        do {
            try installer.installRunnerScript(rhPath: rhPath)
            return SetupStep(.runnerScript, outcome, detail: detail)
        } catch {
            return SetupStep(.runnerScript, .failed, detail: .doctorVerbatim(error.localizedDescription))
        }
    }

    private func cliLinkStep(_ installer: Installer, dryRun: Bool) -> SetupStep {
        let existing = installer.existingCLILinkTarget()
        let link = installer.cliLink.path
        if existing == rhPath { return SetupStep(.cliLink, .unchanged, detail: .doctorVerbatim(link)) }
        let outcome: SetupStep.Outcome = existing == nil ? .created : .updated
        let replaced = existing.map { "; it replaced a link to \($0)" } ?? ""
        if dryRun {
            // A real file or folder with that name is the person's: the link is refused, and a dry run says so.
            if existing == nil, entryExists(installer.cliLink) { return SetupStep(.cliLink, .failed, detail: .doctorVerbatim(InstallError.notALink(path: link).localizedDescription)) }
            return SetupStep(.cliLink, outcome, detail: .doctorVerbatim(link + replaced))
        }
        do {
            try installer.installCLILink(rhPath: rhPath)
            return SetupStep(.cliLink, outcome, detail: .doctorVerbatim(link + replaced))
        } catch {
            return SetupStep(.cliLink, .failed, detail: .doctorVerbatim(error.localizedDescription))
        }
    }

    private func servicesStep(_ installer: Installer, dryRun: Bool, planned: Config?) async -> SetupStep {
        // The Services follow the config as it is now, which this very run may have just created, or, in a dry run, would create.
        let config = planned ?? ConfigStore.load(paths: paths).config
        let specs = ActionRegistry(config: config, facts: facts, localizer: localizer).serviceSpecs(rhPath: rhPath)
        let names = Set(specs.map(ServiceWorkflow.bundleName(for:))).count
        let detail = LocalizedMessage.doctorServicesOk(String(names))
        if installer.servicesAreCurrent(specs) { return SetupStep(.services, .unchanged, detail: detail) }
        let outcome: SetupStep.Outcome = installer.installedServices().isEmpty ? .created : .updated
        // Nothing is installed in a dry run, so it counts what would be (the sentence of the checks says "installed").
        if dryRun { return SetupStep(.services, outcome, detail: .doctorVerbatim("\(names) in all")) }
        do {
            try installer.installServices(specs)
            if systemWide {
                _ = try? await runner.run(ProcessStep(executable: "/System/Library/CoreServices/pbs", arguments: ["-update"]), timeout: .seconds(20))
            }
            return SetupStep(.services, outcome, detail: detail)
        } catch {
            return SetupStep(.services, .failed, detail: .doctorVerbatim(error.localizedDescription))
        }
    }

    private func finderExtensionStep(strict: Bool, dryRun: Bool) async -> SetupStep {
        guard systemWide else {
            return SetupStep(.finderExtension, .skipped, detail: .doctorVerbatim("RH_HOME is set, and the extension's registration is for the whole Mac, so a trial leaves it alone"))
        }
        guard let app else {
            if strict { return SetupStep(.finderExtension, .failed, detail: .doctorVerbatim(InstallError.appNotFound.localizedDescription)) }
            return SetupStep(.finderExtension, .skipped, detail: .doctorVerbatim("Right Here.app is not installed. Quick Actions work without it"))
        }
        let appex = HostApp.extensionURL(in: app).path
        guard FileManager.default.fileExists(atPath: appex) else {
            return SetupStep(.finderExtension, .failed, detail: .doctorVerbatim(InstallError.extensionMissing(path: appex).localizedDescription))
        }
        let manager = FinderExtensionManager(runner: runner)
        let status = await manager.status()
        if status.state == .enabled, status.paths == [appex] { return SetupStep(.finderExtension, .unchanged, detail: .doctorExtensionEnabled(appex)) }
        let outcome: SetupStep.Outcome = status.state == .notRegistered ? .created : .updated
        if dryRun { return SetupStep(.finderExtension, outcome, detail: .doctorVerbatim(appex)) }
        do {
            // A build folder or an old copy registered under the same identifier makes macOS drop the extension.
            var removed: [String] = []
            for stale in status.paths where stale != appex {
                try? await manager.unregister(appexPath: stale)
                removed.append(stale)
            }
            let again = try await manager.registerAndConfirm(appexPath: appex, settle: settle)
            var text = appex
            if !removed.isEmpty { text += "; removed the stale registration of " + removed.joined(separator: ", ") }
            if again { text += "; the first registration did not stay, so it was registered again" }
            return SetupStep(.finderExtension, outcome, detail: .doctorVerbatim(text))
        } catch {
            return SetupStep(.finderExtension, .failed, detail: .doctorVerbatim(error.localizedDescription))
        }
    }
}
