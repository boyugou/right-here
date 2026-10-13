import Foundation
import RightHereCore

/// Checks that everything Right Here needs is in place. Shared by `rh doctor` and the app.
public struct Doctor: Sendable {
    private let facts: any SystemFacts
    private let paths: RHPaths
    private let loaded: LoadedConfig
    private let runner: any ProcessRunner
    private let rhPath: String?

    public init(
        facts: any SystemFacts = LiveSystemFacts(),
        paths: RHPaths,
        loaded: LoadedConfig,
        runner: any ProcessRunner = LiveProcessRunner(),
        rhPath: String? = Installer.currentExecutablePath()
    ) {
        self.facts = facts
        self.paths = paths
        self.loaded = loaded
        self.runner = runner
        self.rhPath = rhPath
    }

    /// - Parameters:
    ///   - probeExtension: Also ask the Finder extension to try the whole chain a menu click uses,
    ///     including permission to control the terminal. It restarts the extension and can make
    ///     macOS show a permission prompt, so it is opt-in.
    ///   - probeLaunch: Go further and have the extension start a throwaway terminal session that
    ///     runs a typed command, the way an agent launch does. It opens and closes a window.
    public func run(probeExtension: Bool = false, probeLaunch: Bool = false, launchPlacement: TerminalPlacement? = nil) async -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        checks.append(configCheck())
        checks += ConfigSync(paths: paths).doctorChecks()
        checks += menuChecks()
        checks += await agentChecks()
        checks.append(claudeLinkCheck())
        checks += integrationChecks()
        checks.append(await extensionCheck())
        checks.append(Self.activityCheck(logFile: paths.logFile))
        if probeLaunch {
            checks.append(await launchCheck(placement: launchPlacement))
        } else if probeExtension {
            checks.append(await chainCheck())
        }
        return checks
    }

    private func launchCheck(placement: TerminalPlacement?) async -> DoctorCheck {
        Self.launchCheck(for: await ExtensionProbe(paths: paths, facts: facts, runner: runner).runLaunch(placement: placement))
    }

    /// What the launch probe reported, as a check. `nil` means the extension never reported back.
    static func launchCheck(for result: LaunchProbe.Result?) -> DoctorCheck {
        let title = "Finder click runs a command in the terminal"
        guard let result else {
            return DoctorCheck(id: "finder.launch", title: title, status: .fail,
                               detail: "the Finder extension did not report back",
                               fix: "Run `rh install --finder`, then try again. See ~/Library/Logs/right-here/rh.log.")
        }
        let name = result.application
        switch result.outcome {
        case .ran:
            var took = result.seconds.map { String(format: " in %.1f s", $0) } ?? ""
            if let accepted = result.accepted { took += String(format: " (request accepted after %.1f s)", accepted) }
            let shell = result.shell.map { "; login shell \($0)" } ?? ""
            return DoctorCheck(id: "finder.launch", title: title, status: .ok, detail: "\(name) ran a typed command in a new session\(took)\(shell)")
        case .timedOut:
            return DoctorCheck(id: "finder.launch", title: title, status: .needsUser, detail: result.detail,
                               fix: "macOS is waiting for you to allow Right Here to control \(name). Click Allow, then run this again.")
        case .denied:
            return DoctorCheck(id: "finder.launch", title: title, status: .fail, detail: "macOS refused to let Right Here control \(name)",
                               fix: "Allow Right Here in System Settings › Privacy & Security › Automation.")
        case .noReply:
            return DoctorCheck(id: "finder.launch", title: title, status: .fail, detail: result.detail,
                               fix: "Check that \(name) starts your shell normally (a slow or interactive startup file can stall it), or choose another terminal with general.terminal.")
        case .wrongFolder:
            return DoctorCheck(id: "finder.launch", title: title, status: .fail, detail: result.detail,
                               fix: "Choose another terminal with general.terminal and report this, with the terminal's name and version.")
        case .notInstalled, .unsupported:
            return DoctorCheck(id: "finder.launch", title: title, status: .warn, detail: result.detail,
                               fix: "Choose a terminal that can run commands with general.terminal (\(KnownApps.commandTerminalPhrase)).")
        case .failed:
            return DoctorCheck(id: "finder.launch", title: title, status: .fail, detail: result.detail,
                               fix: "Run `rh probe launch` in a terminal for details.")
        }
    }

    private func chainCheck() async -> DoctorCheck {
        Self.chainCheck(for: await ExtensionProbe(paths: paths, facts: facts, runner: runner).runAutomation())
    }

    /// What the automation probe reported, as a check. `nil` means the extension never reported back.
    static func chainCheck(for results: [AutomationProbe.Result]?) -> DoctorCheck {
        guard let results else {
            return DoctorCheck(id: "finder.chain", title: "Finder click to terminal", status: .fail,
                               detail: "the Finder extension did not report back",
                               fix: "Run `rh install --finder`, then try again. See ~/Library/Logs/right-here/rh.log.")
        }
        let worst = results.first { $0.outcome != .granted && $0.outcome != .notRunning } ?? results.first
        let summary = results.map { "\($0.application): \($0.outcome.rawValue)" }.joined(separator: ", ")
        switch worst?.outcome {
        case .granted?, .notRunning?:
            return DoctorCheck(id: "finder.chain", title: "Finder click to terminal", status: .ok, detail: summary)
        case .timedOut?:
            return DoctorCheck(id: "finder.chain", title: "Finder click to terminal", status: .needsUser, detail: summary,
                               fix: "macOS is waiting for you to allow Right Here to control the terminal. Click Allow, then run this again.")
        default:
            return DoctorCheck(id: "finder.chain", title: "Finder click to terminal", status: .fail, detail: summary,
                               fix: "Allow Right Here in System Settings › Privacy & Security › Automation.")
        }
    }

    // MARK: Config

    func configCheck() -> DoctorCheck {
        if !loaded.fileExists && !loaded.localFileExists {
            return DoctorCheck(.config, status: .warn, detail: .doctorConfigMissing(loaded.file.path), fix: .doctorFixConfigInit)
        }
        if loaded.result.hasErrors {
            let first = loaded.result.diagnostics.first { $0.severity == .error }
            return DoctorCheck(.config, status: .fail, detail: first.map { .doctorVerbatim($0.summary(file: loaded.file)) }, fix: .doctorFixConfigErrors)
        }
        let warnings = loaded.result.diagnostics.count
        var status: DoctorCheck.Status = warnings == 0 ? .ok : .warn
        var notes: [LocalizedMessage] = []
        if loaded.localFileExists { notes.append(.doctorConfigOverlay(loaded.localFile.path)) }
        for file in [loaded.file, loaded.localFile] where (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) != nil {
            notes.append(.doctorConfigSymlink(file.lastPathComponent))
            status = .warn
        }
        let detail: LocalizedMessage
        if warnings > 0 {
            detail = .doctorConfigWarnings(String(warnings))
        } else {
            detail = loaded.fileExists ? .doctorVerbatim(loaded.file.path) : .doctorConfigMissing(loaded.file.path)
        }
        return DoctorCheck(.config, status: status, detail: detail, notes: notes, fix: warnings == 0 ? nil : .doctorFixConfigWarnings)
    }

    // MARK: Apps and agents

    private func menuChecks() -> [DoctorCheck] {
        let registry = ActionRegistry(config: loaded.config, facts: facts)
        let terminal = registry.info(.openTerminal(nil))
        let editor = registry.info(.openEditor)
        return [
            DoctorCheck(.terminalDefault, status: terminal.available ? .ok : .fail, detail: Self.appDetail(terminal),
                        fix: terminal.available ? nil : .doctorFixTerminal),
            DoctorCheck(.editorDefault, status: editor.available ? .ok : .warn, detail: Self.appDetail(editor),
                        fix: editor.available ? nil : .doctorFixEditor)
        ]
    }

    /// What a default app check says: the app a click opens, or why there is none.
    private static func appDetail(_ app: ActionInfo) -> LocalizedMessage? {
        app.available ? .menuOpenIn(app.shortTitle) : app.unavailableReason.map(LocalizedMessage.doctorVerbatim)
    }

    private func agentChecks() async -> [DoctorCheck] {
        let config = loaded.config
        guard !config.enabledAgents.isEmpty else {
            return [DoctorCheck(.agents, status: .warn, detail: .doctorAgentsNone, fix: .doctorFixAgentsAdd)]
        }
        let registry = ActionRegistry(config: config, facts: facts)
        let commands = config.enabledAgents.compactMap { config.agent(id: $0)?.executable }
        let found = await Detector(facts: facts, runner: runner).commandsFound(commands)
        var checks: [DoctorCheck] = []
        for id in config.enabledAgents {
            guard let agent = config.agent(id: id) else { continue }
            let command = agent.executable
            let action = registry.info(.agent(id: id, variant: nil, launcher: nil))
            if !found.contains(command) {
                checks.append(DoctorCheck(.agent(id), title: agent.name, status: .warn, detail: .doctorAgentNotFound(command), fix: .doctorFixAgentRemove(id)))
            } else if !action.available {
                checks.append(DoctorCheck(.agent(id), title: agent.name, status: .warn, detail: action.unavailableReason.map(LocalizedMessage.doctorVerbatim),
                                          fix: .doctorFixAgentLauncher))
            } else {
                checks.append(DoctorCheck(.agent(id), title: agent.name, status: .ok, detail: .doctorAgentOk(command, action.title)))
            }
        }
        return checks
    }

    private func claudeLinkCheck() -> DoctorCheck {
        let handler = facts.homeDirectory.appendingPathComponent("Applications/Claude Code URL Handler.app")
        guard facts.fileExists(handler) else {
            return DoctorCheck(.claudeLink, status: .warn, detail: .doctorClaudeLinkMissing, fix: .doctorFixClaudeLink)
        }
        return DoctorCheck(.claudeLink, status: .ok, detail: .doctorClaudeLinkOk)
    }

    // MARK: Finder integration

    private func integrationChecks() -> [DoctorCheck] {
        let installer = Installer(home: facts.homeDirectory)
        var checks: [DoctorCheck] = []

        if let target = installer.installedRunnerTarget() {
            let exists = FileManager.default.isExecutableFile(atPath: target)
            let stale = rhPath.map { $0 != target } ?? false
            if !exists {
                checks.append(DoctorCheck(.finderRunner, status: .fail, detail: .doctorRunnerTargetMissing(target), fix: .doctorFixInstallScripts))
            } else if stale {
                checks.append(DoctorCheck(.finderRunner, status: .warn, detail: .doctorRunnerStale(target), fix: .doctorFixInstallScripts))
            } else {
                checks.append(DoctorCheck(.finderRunner, status: .ok, detail: .doctorRunnerOk(target)))
            }
        } else {
            checks.append(DoctorCheck(.finderRunner, status: .fail, detail: .doctorRunnerMissing, fix: .doctorFixInstallScripts))
        }

        checks.append(Self.servicesCheck(
            installed: Set(installer.installedServices().map(\.lastPathComponent)),
            expected: Set(ActionRegistry(config: loaded.config, facts: facts, localizer: .system)
                .serviceSpecs(rhPath: rhPath ?? "rh").map(ServiceWorkflow.bundleName(for:)))))

        let linked = (try? FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path)) != nil
        let onPath = (facts.environment("PATH") ?? "").split(separator: ":").contains { String($0) == installer.locations.localBin.path }
        if !linked {
            checks.append(DoctorCheck(.cliLink, status: .warn, detail: .doctorCliMissing(installer.cliLink.path), fix: .doctorFixInstallCLI))
        } else if !onPath {
            checks.append(DoctorCheck(.cliLink, status: .warn, detail: .doctorCliNotOnPath(installer.cliLink.path), fix: .doctorFixCliPath))
        } else {
            checks.append(DoctorCheck(.cliLink, status: .ok, detail: .doctorVerbatim(installer.cliLink.path)))
        }
        return checks
    }

    /// Evidence that a click in Finder has reached `rh`: the newest successful action in the run log that
    /// did not come from the command line. Informational; nothing here is wrong when there is none yet.
    static func activityCheck(logFile: URL, now: Date = Date()) -> DoctorCheck {
        let text = [logFile, logFile.appendingPathExtension("1")]
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        for line in text.split(separator: "\n").reversed() {
            guard let entry = RunLog.Entry(parsing: line), entry.origin != .cli else { continue }
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .full
            return DoctorCheck(.finderActivity, status: .ok,
                               detail: .doctorActivityRecent(entry.actionID, entry.origin.rawValue, relative.localizedString(for: entry.date, relativeTo: now)))
        }
        return DoctorCheck(.finderActivity, status: .ok, detail: .doctorActivityNone)
    }

    /// Compares the Services on disk with the ones the config asks for: they are files written by
    /// `rh install --services`, so editing the config does not change them by itself.
    static func servicesCheck(installed: Set<String>, expected: Set<String>) -> DoctorCheck {
        if installed.isEmpty {
            return DoctorCheck(.services, status: .warn, detail: .doctorServicesNone, fix: .doctorFixInstallServices)
        }
        if installed == expected {
            return DoctorCheck(.services, status: .ok, detail: .doctorServicesOk(String(installed.count)))
        }
        let missing = expected.subtracting(installed).count
        let stale = installed.subtracting(expected).count
        return DoctorCheck(.services, status: .warn, detail: .doctorServicesDiffer(String(installed.count), String(missing), String(stale)), fix: .doctorFixInstallServices)
    }

    private func extensionCheck() async -> DoctorCheck {
        let status = await FinderExtensionManager(runner: runner).status()
        switch status.state {
        case .notRegistered:
            return DoctorCheck(.finderExtension, status: .fail, detail: .doctorExtensionNotRegistered, fix: .doctorFixExtensionInstall)
        case .disabled:
            return DoctorCheck(.finderExtension, status: .needsUser, detail: .doctorExtensionDisabled, fix: .doctorFixExtensionEnable)
        case .enabled:
            if status.paths.count > 1 {
                return DoctorCheck(.finderExtension, status: .warn, detail: .doctorExtensionMultiple(String(status.paths.count), status.paths.joined(separator: "; ")),
                                   fix: .doctorFixExtensionClean)
            }
            return DoctorCheck(.finderExtension, status: .ok, detail: status.paths.first.map(LocalizedMessage.doctorVerbatim))
        }
    }
}
