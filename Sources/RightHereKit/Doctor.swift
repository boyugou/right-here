import Foundation
import RightHereCore

public struct DoctorCheck: Sendable, Equatable, Codable {
    public enum Status: String, Sendable, Codable {
        case ok
        case warn
        case fail
        /// Only the person can fix it, for example by switching a Finder extension on in System Settings.
        case needsUser = "needs-user"
    }

    public var id: String
    public var title: String
    public var status: Status
    public var detail: String?
    public var fix: String?

    public init(id: String, title: String, status: Status, detail: String? = nil, fix: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.fix = fix
    }
}

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
                               fix: "Choose a terminal that can run commands with general.terminal (Ghostty or Terminal).")
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

    private func configCheck() -> DoctorCheck {
        if !loaded.fileExists {
            return DoctorCheck(id: "config", title: "Config file", status: .warn,
                               detail: "none at \(loaded.file.path); defaults apply", fix: "Run `rh init`.")
        }
        if loaded.result.hasErrors {
            let first = loaded.result.diagnostics.first { $0.severity == .error }
            return DoctorCheck(id: "config", title: "Config file", status: .fail,
                               detail: first.map { $0.summary(file: loaded.file) },
                               fix: "Run `rh config validate` and fix the errors.")
        }
        let warnings = loaded.result.diagnostics.count
        var detail = warnings == 0 ? loaded.file.path : "\(warnings) warning(s); run `rh config validate`"
        var status: DoctorCheck.Status = warnings == 0 ? .ok : .warn
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: loaded.file.path)) != nil {
            detail += "; the file is a symlink, which the Finder extension's sandbox may not be able to follow"
            status = .warn
        }
        return DoctorCheck(id: "config", title: "Config file", status: status, detail: detail,
                           fix: warnings == 0 ? nil : "Run `rh config validate`; warnings are usually typos, and what they were meant to set is missing.")
    }

    // MARK: Apps and agents

    private func menuChecks() -> [DoctorCheck] {
        let registry = ActionRegistry(config: loaded.config, facts: facts)
        let terminal = registry.info(.openTerminal(nil))
        let editor = registry.info(.openEditor)
        return [
            DoctorCheck(id: "terminal.default", title: "Default terminal", status: terminal.available ? .ok : .fail,
                        detail: terminal.available ? terminal.title : terminal.unavailableReason,
                        fix: terminal.available ? nil : "Install a terminal or set general.terminal."),
            DoctorCheck(id: "editor.default", title: "Default editor", status: editor.available ? .ok : .warn,
                        detail: editor.available ? editor.title : editor.unavailableReason,
                        fix: editor.available ? nil : "Install an editor or set general.editor.")
        ]
    }

    private func agentChecks() async -> [DoctorCheck] {
        let config = loaded.config
        guard !config.enabledAgents.isEmpty else {
            return [DoctorCheck(id: "agents", title: "Agents", status: .warn, detail: "none enabled",
                                fix: "Add agents to general.agents, for example agents = [\"claude\"].")]
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
                checks.append(DoctorCheck(id: "agent.\(id)", title: agent.name, status: .warn,
                                          detail: "`\(command)` is not found in your login shell",
                                          fix: "Install it, or remove \"\(id)\" from general.agents."))
            } else if !action.available {
                checks.append(DoctorCheck(id: "agent.\(id)", title: agent.name, status: .warn, detail: action.unavailableReason,
                                          fix: "Choose another terminal with general.terminal, or set launcher = \"link\" or \"desktop\"."))
            } else {
                checks.append(DoctorCheck(id: "agent.\(id)", title: agent.name, status: .ok,
                                          detail: "`\(command)` found; starts with \(action.title)"))
            }
        }
        return checks
    }

    private func claudeLinkCheck() -> DoctorCheck {
        let handler = facts.homeDirectory.appendingPathComponent("Applications/Claude Code URL Handler.app")
        let present = facts.fileExists(handler)
        return DoctorCheck(id: "claude.link", title: "Claude Code terminal link", status: present ? .ok : .warn,
                           detail: present ? "handler installed" : "handler not installed (only needed for launcher = \"link\")",
                           fix: present ? nil : "Start `claude` once and send a prompt; Claude Code registers the handler.")
    }

    // MARK: Finder integration

    private func integrationChecks() -> [DoctorCheck] {
        let installer = Installer(home: facts.homeDirectory)
        var checks: [DoctorCheck] = []

        if let target = installer.installedRunnerTarget() {
            let exists = FileManager.default.isExecutableFile(atPath: target)
            let stale = rhPath.map { $0 != target } ?? false
            checks.append(DoctorCheck(
                id: "finder.runner", title: "Finder runner script",
                status: exists ? (stale ? .warn : .ok) : .fail,
                detail: exists ? (stale ? "points at \(target), not at this rh" : "runs \(target)") : "points at \(target), which does not exist",
                fix: exists && !stale ? nil : "Run `rh install --scripts`."))
        } else {
            checks.append(DoctorCheck(id: "finder.runner", title: "Finder runner script", status: .fail,
                                      detail: "not installed; the Finder menu cannot run actions",
                                      fix: "Run `rh install --scripts`."))
        }

        checks.append(Self.servicesCheck(
            installed: Set(installer.installedServices().map(\.lastPathComponent)),
            expected: Set(ActionRegistry(config: loaded.config, facts: facts, localizer: .system)
                .serviceSpecs(rhPath: rhPath ?? "rh").map(ServiceWorkflow.bundleName(for:)))))

        let linked = (try? FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path)) != nil
        let onPath = (facts.environment("PATH") ?? "").split(separator: ":").contains { String($0) == installer.locations.localBin.path }
        checks.append(DoctorCheck(
            id: "cli.link", title: "rh on your PATH",
            status: linked && onPath ? .ok : .warn,
            detail: linked ? (onPath ? installer.cliLink.path : "linked at \(installer.cliLink.path), but that folder is not on PATH") : "no link at \(installer.cliLink.path)",
            fix: linked && onPath ? nil : (linked ? "Add ~/.local/bin to PATH in your shell profile." : "Run `rh install --cli`.")))
        return checks
    }

    /// Evidence that a click in Finder has reached `rh`: the newest successful action in the run log that
    /// did not come from the command line. Informational; nothing here is wrong when there is none yet.
    static func activityCheck(logFile: URL, now: Date = Date()) -> DoctorCheck {
        let title = "Last action started from Finder"
        let text = [logFile, logFile.appendingPathExtension("1")]
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        for line in text.split(separator: "\n").reversed() {
            guard let entry = RunLog.Entry(parsing: line), entry.origin != .cli else { continue }
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .full
            return DoctorCheck(id: "finder.activity", title: title, status: .ok,
                               detail: "\(entry.actionID) from the \(entry.origin.rawValue) menu, \(relative.localizedString(for: entry.date, relativeTo: now))")
        }
        return DoctorCheck(id: "finder.activity", title: title, status: .ok,
                           detail: "none yet; right-click a folder in Finder and choose an action, then run `rh doctor` again")
    }

    /// Compares the Services on disk with the ones the config asks for: they are files written by
    /// `rh install --services`, so editing the config does not change them by itself.
    static func servicesCheck(installed: Set<String>, expected: Set<String>) -> DoctorCheck {
        if installed.isEmpty {
            return DoctorCheck(id: "services", title: "Finder Services", status: .warn,
                               detail: "none installed; Quick Actions and keyboard shortcuts are not available",
                               fix: "Run `rh install --services`.")
        }
        if installed == expected {
            return DoctorCheck(id: "services", title: "Finder Services", status: .ok, detail: "\(installed.count) installed")
        }
        let missing = expected.subtracting(installed).count
        let stale = installed.subtracting(expected).count
        return DoctorCheck(id: "services", title: "Finder Services", status: .warn,
                           detail: "\(installed.count) installed, but they differ from the config (\(missing) missing, \(stale) stale)",
                           fix: "Run `rh install --services`.")
    }

    private func extensionCheck() async -> DoctorCheck {
        let status = await FinderExtensionManager(runner: runner).status()
        switch status.state {
        case .notRegistered:
            return DoctorCheck(id: "finder.extension", title: "Finder extension", status: .fail,
                               detail: "not registered; Finder shows no Right Here menu",
                               fix: "Install Right Here.app, then run `rh install --finder`.")
        case .disabled:
            return DoctorCheck(id: "finder.extension", title: "Finder extension", status: .needsUser,
                               detail: "registered but switched off",
                               fix: "Run `rh install --finder`, or switch on Right Here in System Settings › General › Login Items & Extensions › Finder.")
        case .enabled:
            if status.paths.count > 1 {
                return DoctorCheck(id: "finder.extension", title: "Finder extension", status: .warn,
                                   detail: "enabled, but registered from \(status.paths.count) locations: " + status.paths.joined(separator: "; "),
                                   fix: "Run `rh install --finder` to remove the stale copies.")
            }
            return DoctorCheck(id: "finder.extension", title: "Finder extension", status: .ok, detail: status.paths.first)
        }
    }
}
