import Foundation

/// One application as `rh apps` and the MCP catalog tool list it.
public struct AppRow: Sendable, Equatable, Encodable {
    public var id: String
    public var name: String
    public var role: String
    public var installed: Bool
    public var bundleID: String?
}

/// One agent as `rh agents`, the MCP catalog tool and the App Intents (which read `rh agents --json` back) list it.
public struct AgentRow: Sendable, Equatable, Codable {
    public var id: String
    public var name: String
    public var command: String
    public var enabled: Bool
    /// Whether the login shell finds the command; `nil` when nobody asked it, which takes a shell that only `rh agents` starts.
    public var foundInShell: Bool?
    /// Where the login shell finds the command (what `command -v` says: a path, or the name of an alias or a function); `nil` when it was not found or not asked.
    public var location: String?
    /// The agent's own page that says how to install it (`AgentDescriptor.installPage`).
    public var installPage: String?
    public var variants: [String]
    public var terminalLink: Bool
    public var desktopLink: Bool
    /// How the command takes a first prompt (`positional` or a flag); `nil` when it is not known, which keeps presets away.
    public var promptArgument: String?
    /// The flag this agent uses to bypass tool confirmation prompts, if known.
    public var bypassPermissionArgument: String?
    /// Whether the agent starts with its own permission prompts switched off on this machine (`general.bypass_permissions` or `[agent.<id>] bypass_permissions`).
    public var bypassPermissions: Bool

    /// How `rh agents` words the row, not part of its JSON: whether the agent is on, and what the login shell found. An agent
    /// that is on but not found still has its entry in the menu, which cannot look (that takes a shell); only this says so.
    public var stateText: String {
        // A path is what a person checks against their PATH; an alias or a function has none to show.
        let at = location.flatMap { $0.hasPrefix("/") ? " at " + $0.withControlCharactersEscaped : nil } ?? ""
        if enabled {
            let state = foundInShell == false ? "enabled, not found" : foundInShell == true ? "enabled, found" + at : "enabled"
            return bypassPermissions ? state + ", permission prompts off" : state
        }
        switch foundInShell {
        case true?: return "found" + at + ", not enabled"
        case false?: return installPage.map { "not found; to install it, see " + $0 } ?? "not found"
        // Nobody asked the shell, or it said nothing: neither is "not found".
        case nil: return "not enabled"
        }
    }
}

extension Config {
    public func appRows(facts: any SystemFacts) -> [AppRow] {
        allApps.map { app in
            let bundleID = app.installedBundleID(facts: facts)
            return AppRow(id: app.id, name: app.name, role: app.role.rawValue, installed: bundleID != nil, bundleID: bundleID)
        }
    }

    /// - Parameters:
    ///   - found: The commands the login shell found among those of the agents, or `nil` when nobody asked it.
    ///   - shellAnswered: Whether the shell got to the end of its answer. When it did not, a command it did not name is unknown and not "not found".
    ///   - locations: What the login shell said of each command it found (`command -v`).
    public func agentRows(found: Set<String>? = nil, shellAnswered: Bool = true, locations: [String: String] = [:]) -> [AgentRow] {
        allAgents.map { agent in
            AgentRow(
                id: agent.id, name: agent.name, command: agent.command,
                enabled: enabledAgents.contains(agent.id),
                foundInShell: found.flatMap { $0.contains(agent.executable) ? true : (shellAnswered ? false : nil) },
                location: found?.contains(agent.executable) == true ? locations[agent.executable] : nil,
                installPage: agent.installPage?.absoluteString,
                variants: agent.variants.map(\.id), terminalLink: agent.terminalLink != nil, desktopLink: agent.desktopLink != nil,
                promptArgument: agent.promptArgument?.configValue,
                bypassPermissionArgument: agent.bypassPermissionArgument,
                bypassPermissions: flagThatSkipsPrompts(for: agent) != nil
            )
        }
    }
}
