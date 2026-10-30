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
    /// The setup window runs it, and shows the checks it ends with: the doctor's login shell is asked about every agent the config knows, not only the
    /// enabled ones (the window shows which are installed, `SetupReport.shell`), and a time is written in the language of the window. The command line has
    /// no use for the first and writes English.
    public var isForTheWindow = false
    /// Whether the config may be made when there is none. The first run makes it from the person's choices; Install or Repair does not, so that a config is never
    /// made from what was found without the choice being asked for.
    public var createsConfig: Bool

    public init(pieces: Set<SetupPiece>, choices: SetupChoices = SetupChoices(), force: Bool = false, dryRun: Bool = false, checkup: Bool = false, strict: Bool = false,
                createsConfig: Bool = true) {
        self.pieces = pieces
        self.choices = choices
        self.force = force
        self.dryRun = dryRun
        self.checkup = checkup
        self.strict = strict
        self.createsConfig = createsConfig
    }

    /// Install or Repair: every piece, then the doctor, and no config made.
    public static func repair() -> SetupRequest {
        SetupRequest(pieces: Set(SetupPiece.allCases), checkup: true, createsConfig: false)
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
/// What a setup is doing now, for a window that shows it while it runs: a full run takes seconds, and a button that only greys out for that long looks stuck.
public enum SetupPhase: Sendable, Equatable {
    /// Another setup holds the lock, and this one waits for it to end.
    case waiting
    case piece(SetupPiece)
    /// The doctor's checks, at the end.
    case checkup

    /// What `rh setup` prints while it lasts, on a terminal: the window's sentence, in English like the rest of the command line.
    public var englishLine: String { Localizer.english.string(messageKey) }

    /// What the window says while it lasts.
    public var messageKey: LocalizationKey {
        switch self {
        case .waiting: .appSetupPhaseWaiting
        case .piece(let piece): piece.progressKey
        case .checkup: .appSetupPhaseCheckup
        }
    }
}

public struct SetupRunner: Sendable {
    private let facts: any SystemFacts
    private let paths: RHPaths
    private let runner: any ProcessRunner
    private let rhPath: String
    private let app: URL?
    private let trialHome: URL?
    private let systemWide: Bool
    /// The language of the names of the Quick Actions; `nil`: the config's (`Config.localizer`).
    private let localizer: Localizer?
    private let settle: Duration
    private let lockTimeout: Duration

    /// - Parameters:
    ///   - rhPath: The `rh` that the runner script and the Quick Actions run: the one inside Right Here.app for the app, the running
    ///     one for the command line.
    ///   - app: The Right Here.app that has the Finder extension: the one that holds `rhPath`, or the installed one; `nil` when there is none.
    ///   - trialHome: The folder `RH_HOME` names, when it is set.
    ///   - systemWide: Whether what is registered for the whole Mac may be changed. By default, when there is no trial home.
    ///   - lockTimeout: How long a setup waits for another one that is running (the setup window, `rh setup` in a terminal, an AI agent's)
    ///     before it gives up. A full run takes seconds: the extension is registered and given three to settle, and the doctor starts the login shell.
    public init(facts: any SystemFacts = LiveSystemFacts(), paths: RHPaths? = nil, runner: any ProcessRunner = LiveProcessRunner(), rhPath: String, app: URL?,
                trialHome: URL? = LiveSystemFacts.homeOverride, systemWide: Bool? = nil, localizer: Localizer? = nil, settle: Duration = .seconds(3),
                lockTimeout: Duration = .seconds(120)) {
        self.facts = facts
        self.paths = paths ?? RHPaths.current(facts: facts)
        self.runner = runner
        self.rhPath = rhPath
        self.app = app
        self.trialHome = trialHome
        self.systemWide = systemWide ?? (trialHome == nil)
        self.localizer = localizer
        self.settle = settle
        self.lockTimeout = lockTimeout
    }

    /// - Parameter progress: Told of each phase before it starts.
    public func run(_ request: SetupRequest, progress: @Sendable (SetupPhase) async -> Void = { _ in }) async throws -> SetupReport {
        // The runner script and the Services would point into a folder that disappears when the app quits.
        if let problem = InstallError.problem(runningFrom: rhPath) { throw problem }
        if let problem = InstallError.problem(helper: rhPath, version: AppIdentity.version, copies: facts.applicationCopies(bundleID: AppIdentity.hostBundleID),
                                              home: facts.homeDirectory.path) { throw problem }
        // One setup at a time: a second one waits its turn and then finds everything in place, which it says. A dry run writes nothing, so
        // it neither waits nor makes the lock file (and the folder of it).
        var turn: FileLock?
        if !request.dryRun {
            do {
                turn = try? await FileLock.acquire(paths.setupLockFile, timeout: .zero)
                if turn == nil {
                    await progress(.waiting)
                    turn = try await FileLock.acquire(paths.setupLockFile, timeout: lockTimeout)
                }
            } catch is FileLock.Busy { throw InstallError.anotherSetupIsRunning }
        }
        defer { turn?.release() }
        let installer = Installer(home: facts.homeDirectory)
        var report = SetupReport(dryRun: request.dryRun, trialHome: trialHome?.path)

        // What a dry run would have written: the Quick Actions of the plan are counted from it, not from a file that is not there yet.
        var planned: ConfigLoadResult?
        for piece in SetupPiece.allCases where request.pieces.contains(piece) {
            await progress(.piece(piece))
            switch piece {
            case .config: planned = await configStep(request, into: &report)
            case .runnerScript: report.steps.append(runnerScriptStep(installer, dryRun: request.dryRun))
            case .cliLink: report.steps.append(cliLinkStep(installer, dryRun: request.dryRun))
            case .services:
                report.steps.append(await servicesStep(installer, dryRun: request.dryRun, planned: planned, configReported: report.step(.config)?.outcome == .failed))
            case .finderExtension: report.steps.append(await finderExtensionStep(strict: request.strict, dryRun: request.dryRun))
            }
        }

        let loaded = ConfigStore.load(paths: paths)
        // A config that cannot be used is the first thing left for the person, and nothing is derived from it: what the config says would be
        // the defaults, which is not what the person has.
        let problem = request.pieces.isDisjoint(with: [.config, .services]) ? nil : ConfigProblem(planned ?? loaded.result, paths: paths)
        if let problem { report.needsUser.append(SetupAdvice.configNeed(problem, command: request.englishCommand)) }
        if request.checkup, !request.dryRun {
            await progress(.checkup)
            let examined = await Doctor(facts: facts, paths: paths, loaded: loaded, runner: runner, rhPath: rhPath).examine(everyAgent: request.isForTheWindow, language: request.isForTheWindow ? loaded.config.localizer.resolvedLanguage : "en")
            var rows = examined.checks
            report.shell = examined.shell
            // What a trial says about the Finder extension and the copies of the app is what this Mac says, not what the trial did.
            if !systemWide { rows.removeAll { $0.id == .finderExtension || $0.id == .appCopies } }
            report.checks = rows
            report.needsUser += SetupAdvice.needsUser(checks: rows, config: problem == nil ? loaded.config : nil, facts: facts)
        }
        report.warnings += notes(editsPending: !report.configEdits.isEmpty)
        report.next = request.checkup ? SetupAdvice.next(configEdits: report.configEdits, needs: report.needsUser, checked: !request.dryRun,
                                                         rerun: request.dryRun ? request.englishCommand : nil, command: request.englishCommand) : []
        return report
    }

    // MARK: Notes

    private func notes(editsPending: Bool) -> [String] {
        var notes: [String] = []
        if let trialHome, !systemWide {
            notes.append("RH_HOME is set, so this is a trial: the config, the runner script, the command link and the Quick Actions are under \(trialHome.path), and the Finder extension, which is registered for the whole Mac, was neither changed nor checked. The commands under Next act on this trial only while RH_HOME is set for them too.")
        }
        if systemWide, HostApp.isBuildProduct(rhPath) {
            notes.append("This rh runs from a build folder (\(rhPath)), and the runner script and the Quick Actions now point at it: they stop working when that folder is cleaned. For a lasting setup run the rh inside Right Here.app (Right Here.app/Contents/Helpers/rh setup).")
        }
        if editsPending {
            notes.append("\(paths.configFile.lastPathComponent) already exists, so Right Here left it alone and did not apply your choices.")
        }
        return notes
    }

    // MARK: Pieces

    private func entryExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// - Returns: In a dry run that would write a config, the config it would write; otherwise `nil`, and what depends on the config reads the file.
    private func configStep(_ request: SetupRequest, into report: inout SetupReport) async -> ConfigLoadResult? {
        let exists = entryExists(paths.configFile)
        if exists, !request.force {
            existingConfigStep(request, into: &report, madeJustNow: false)
            return nil
        }
        // Only the per-machine overlay is there, or nothing: a repair does not make the base config from what it found.
        if !exists, !request.createsConfig {
            report.steps.append(SetupStep(.config, .skipped, detail: .doctorVerbatim("there is no \(paths.configFile.lastPathComponent); the first run's Set Up makes it from your choices")))
            return nil
        }

        var detected = DetectedEnvironment()
        let choices = request.choices
        if choices.terminal == nil || choices.editor == nil || choices.agents == nil {
            let looked = await Detector(facts: facts, runner: runner).look()
            detected = looked.environment
            // "Whatever you find" with a shell that found nothing because it said nothing makes a config with no agents, and nobody would know why.
            if choices.agents == nil, !looked.shellAnswered {
                report.warnings.append("Your login shell did not say which AI agents are installed (a startup file that exits or waits does that), so none was chosen. Say which you use with --agents, for example --agents claude,codex.")
            }
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
                // A config appeared between the check and the write (the setup window, or another terminal): it is the one that stays, and
                // it is read like any config that was there: what the person chose is not in it, so the edits are listed.
                report.chosen = nil
                existingConfigStep(request, into: &report, madeJustNow: true)
            }
        } catch {
            report.steps.append(SetupStep(.config, .failed, detail: .doctorVerbatim(error.localizedDescription)))
            report.chosen = nil
        }
        return nil
    }

    /// A config that is there is the person's, so setup never rewrites it. The step says whether it can be used at all (it fails when it
    /// cannot, and nothing is computed from it), and otherwise what would make it say what was asked for.
    private func existingConfigStep(_ request: SetupRequest, into report: inout SetupReport, madeJustNow: Bool) {
        let loaded = ConfigStore.load(paths: paths)
        if let problem = ConfigProblem(loaded.result, paths: paths) {
            report.steps.append(SetupStep(.config, .failed, detail: .doctorVerbatim("\(problem.sentence), so setup left it as it is and made nothing from it")))
            return
        }
        let detail = madeJustNow ? "\(paths.configFile.path) was made a moment ago by something else: it is kept" : "\(paths.configFile.path); it is yours, so setup never rewrites it"
        report.steps.append(SetupStep(.config, .unchanged, detail: .doctorVerbatim(detail)))
        guard !request.choices.isEmpty else { return }
        func text(_ file: URL) -> String? {
            if case .text(let text) = ConfigStore.text(of: file) { return text }
            return nil
        }
        report.configEdits = ConfigEdits.needed(for: request.choices, config: loaded.config, base: text(paths.configFile), local: text(paths.localConfigFile),
                                                baseName: paths.configFile.lastPathComponent, localName: paths.localConfigFile.lastPathComponent)
    }

    /// The config that a run with these choices would create, with the per-machine overlay on top as it is read now.
    private func plannedConfig(_ written: DetectedEnvironment) -> ConfigLoadResult {
        let local: ConfigSource
        switch ConfigStore.text(of: paths.localConfigFile) {
        case .absent: local = .absent
        case .text(let text): local = .text(text)
        case .problem(let message): local = .unreadable(ConfigDiagnostic(severity: .error, path: "", message: message))
        }
        return ConfigLayers.load(base: .text(ConfigTemplate.render(written)), local: local, overlayName: paths.localConfigFile.lastPathComponent)
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

    private func servicesStep(_ installer: Installer, dryRun: Bool, planned: ConfigLoadResult?, configReported: Bool) async -> SetupStep {
        // The Services follow the config as it is now, which this very run may have just created, or, in a dry run, would create.
        let loaded = planned ?? ConfigStore.load(paths: paths).result
        // Made from a config that cannot be used they would be the defaults', and they would replace the person's: the ones that are there stay.
        // When the config step has said so already, this one is left out; when it has not (one piece asked for by name, or the per-machine
        // overlay is what cannot be used), it is the step that cannot be done.
        if let problem = ConfigProblem(loaded, paths: paths) {
            if configReported {
                return SetupStep(.services, .skipped, detail: .doctorVerbatim("they are made from the config, which cannot be used (see the config file above); the ones that are there were left as they are"))
            }
            return SetupStep(.services, .failed, detail: .doctorVerbatim("they are made from the config, and \(problem.sentence); the ones that are there were left as they are"))
        }
        let config = loaded.config
        let specs = ActionRegistry(config: config, facts: facts, localizer: localizer ?? config.localizer).serviceSpecs(rhPath: rhPath)
        let names = ServiceWorkflow.distinct(specs).count
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
            var removed: [String] = [], kept: [String] = []
            for stale in status.paths where stale != appex {
                do {
                    try await manager.unregister(appexPath: stale)
                    removed.append(stale)
                } catch {
                    kept.append("\(stale) (\(error.localizedDescription))")
                }
            }
            let again = try await manager.registerAndConfirm(appexPath: appex, settle: settle)
            var text = appex
            if !removed.isEmpty { text += "; removed the stale registration of " + removed.joined(separator: ", ") }
            if !kept.isEmpty { text += "; could not remove the stale registration of " + kept.joined(separator: ", ") }
            if again { text += "; the first registration did not stay, so it was registered again" }
            return SetupStep(.finderExtension, outcome, detail: .doctorVerbatim(text))
        } catch {
            return SetupStep(.finderExtension, .failed, detail: .doctorVerbatim(error.localizedDescription))
        }
    }
}
