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
        rhPath: String? = Bundle.main.executableURL?.resolvingSymlinksInPath().path
    ) {
        self.facts = facts
        self.paths = paths
        self.loaded = loaded
        self.runner = runner
        self.rhPath = rhPath
    }

    public func run() async -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        checks.append(configCheck())
        checks += menuChecks()
        checks += await agentChecks()
        checks.append(claudeLinkCheck())
        checks += integrationChecks()
        checks.append(await extensionCheck())
        return checks
    }

    // MARK: Config

    private func configCheck() -> DoctorCheck {
        if !loaded.fileExists {
            return DoctorCheck(id: "config.file", title: "Config file", status: .warn,
                               detail: "none at \(loaded.file.path); defaults apply", fix: "Run `rh init`.")
        }
        if loaded.result.hasErrors {
            let first = loaded.result.diagnostics.first { $0.severity == .error }
            return DoctorCheck(id: "config.valid", title: "Config file", status: .fail,
                               detail: first.map { Self.describe($0, file: loaded.file) },
                               fix: "Run `rh config validate` and fix the errors.")
        }
        let warnings = loaded.result.diagnostics.count
        var detail = warnings == 0 ? loaded.file.path : "\(warnings) warning(s); run `rh config validate`"
        var status: DoctorCheck.Status = warnings == 0 ? .ok : .warn
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: loaded.file.path)) != nil {
            detail += "; the file is a symlink, which the Finder extension's sandbox may not be able to follow"
            status = .warn
        }
        return DoctorCheck(id: "config.valid", title: "Config file", status: status, detail: detail)
    }

    public static func describe(_ diagnostic: ConfigDiagnostic, file: URL) -> String {
        var text = "\(diagnostic.severity.rawValue): \(file.lastPathComponent)"
        if let line = diagnostic.line { text += ":\(line)" }
        if !diagnostic.path.isEmpty { text += " [\(diagnostic.path)]" }
        text += ": \(diagnostic.message)"
        if let suggestion = diagnostic.suggestion { text += " (\(suggestion))" }
        return text
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
        func firstWord(_ command: String) -> String { command.split(separator: " ").first.map(String.init) ?? command }
        let commands = config.enabledAgents.compactMap { config.agent(id: $0).map { firstWord($0.command) } }
        let found = await Detector(facts: facts, runner: runner).commandsFound(commands)
        var checks: [DoctorCheck] = []
        for id in config.enabledAgents {
            guard let agent = config.agent(id: id) else { continue }
            let command = firstWord(agent.command)
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

        let services = installer.installedServices()
        checks.append(DoctorCheck(
            id: "services", title: "Finder Services", status: services.isEmpty ? .warn : .ok,
            detail: services.isEmpty ? "none installed; Quick Actions and keyboard shortcuts are not available" : "\(services.count) installed",
            fix: services.isEmpty ? "Run `rh install --services`." : nil))

        let linked = (try? FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path)) != nil
        let onPath = (facts.environment("PATH") ?? "").split(separator: ":").contains { String($0) == installer.locations.localBin.path }
        checks.append(DoctorCheck(
            id: "cli.link", title: "rh on your PATH",
            status: linked && onPath ? .ok : .warn,
            detail: linked ? (onPath ? installer.cliLink.path : "linked at \(installer.cliLink.path), but that folder is not on PATH") : "no link at \(installer.cliLink.path)",
            fix: linked && onPath ? nil : (linked ? "Add ~/.local/bin to PATH in your shell profile." : "Run `rh install --cli`.")))
        return checks
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
