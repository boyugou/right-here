import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check that everything Right Here needs is in place.",
        discussion: "Each check has a status (ok, warn, fail, needs-user) and, when something is wrong, a fix. Exits with status 1 if any check fails."
    )

    @Flag(help: "Print JSON.")
    var json = false

    func run() async throws {
        let runtime = Runtime()
        let checks = await DoctorChecks(runtime: runtime).run()
        if json {
            try Output.json(DoctorReport(ok: !checks.contains { $0.status == .fail }, checks: checks))
        } else {
            for check in checks {
                Output.print("[\(check.status.rawValue)] \(check.title)" + (check.detail.map { ": \($0)" } ?? ""))
                if let fix = check.fix { Output.print("       fix: \(fix)") }
            }
        }
        if checks.contains(where: { $0.status == .fail }) { throw ExitCode(1) }
    }
}

struct DoctorReport: Encodable {
    var ok: Bool
    var checks: [DoctorCheck]
}

struct DoctorCheck: Encodable {
    enum Status: String, Encodable {
        case ok, warn, fail
        case needsUser = "needs-user"
    }

    var id: String
    var title: String
    var status: Status
    var detail: String?
    var fix: String?
}

struct DoctorChecks {
    let runtime: Runtime

    func run() async -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        let facts = runtime.facts
        let loaded = runtime.loaded

        if !loaded.fileExists {
            checks.append(.init(id: "config.file", title: "Config file", status: .warn, detail: "none at \(loaded.file.path); defaults apply", fix: "Run `rh init`."))
        } else if loaded.result.hasErrors {
            let first = loaded.result.diagnostics.first { $0.severity == .error }
            checks.append(.init(id: "config.valid", title: "Config file", status: .fail, detail: first.map { Output.describe($0, file: loaded.file) }, fix: "Run `rh config validate` and fix the errors."))
        } else {
            let warnings = loaded.result.diagnostics.count
            checks.append(.init(id: "config.valid", title: "Config file", status: warnings == 0 ? .ok : .warn, detail: warnings == 0 ? loaded.file.path : "\(warnings) warning(s); run `rh config validate`"))
        }

        let registry = ActionRegistry(config: runtime.config, facts: facts)
        let terminal = registry.info(.openTerminal(nil))
        checks.append(.init(id: "terminal.default", title: "Default terminal", status: terminal.available ? .ok : .fail,
                            detail: terminal.available ? terminal.title : terminal.unavailableReason,
                            fix: terminal.available ? nil : "Install a terminal or set general.terminal."))
        let editor = registry.info(.openEditor)
        checks.append(.init(id: "editor.default", title: "Default editor", status: editor.available ? .ok : .warn,
                            detail: editor.available ? editor.title : editor.unavailableReason,
                            fix: editor.available ? nil : "Install an editor or set general.editor."))

        let enabled = runtime.config.enabledAgents
        if enabled.isEmpty {
            checks.append(.init(id: "agents", title: "Agents", status: .warn, detail: "none enabled", fix: "Add agents to general.agents, for example agents = [\"claude\"]."))
        } else {
            let commands = enabled.compactMap { runtime.config.agent(id: $0)?.command.split(separator: " ").first.map(String.init) }
            let found = await Detector(facts: facts).commandsFound(commands)
            for id in enabled {
                guard let agent = runtime.config.agent(id: id) else { continue }
                let command = agent.command.split(separator: " ").first.map(String.init) ?? agent.command
                let action = registry.info(.agent(id: id, variant: nil, launcher: nil))
                if !found.contains(command) {
                    checks.append(.init(id: "agent.\(id)", title: agent.name, status: .warn, detail: "`\(command)` is not found in your login shell", fix: "Install it, or remove \"\(id)\" from general.agents."))
                } else if !action.available {
                    checks.append(.init(id: "agent.\(id)", title: agent.name, status: .warn, detail: action.unavailableReason, fix: "Choose another terminal with general.terminal, or set launcher = \"link\" or \"desktop\"."))
                } else {
                    checks.append(.init(id: "agent.\(id)", title: agent.name, status: .ok, detail: "`\(command)` found; starts with \(action.title)"))
                }
            }
        }

        let handler = facts.homeDirectory.appendingPathComponent("Applications/Claude Code URL Handler.app")
        checks.append(.init(id: "claude.link", title: "Claude Code terminal link", status: facts.fileExists(handler) ? .ok : .warn,
                            detail: facts.fileExists(handler) ? "handler installed" : "handler not installed (only needed for launcher = \"link\")",
                            fix: facts.fileExists(handler) ? nil : "Start `claude` once and send a prompt; Claude Code registers the handler."))
        return checks
    }
}
