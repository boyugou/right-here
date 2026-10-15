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
        if enabled {
            let state = foundInShell == false ? "enabled, not found" : "enabled"
            return bypassPermissions ? state + ", permission prompts off" : state
        }
        return foundInShell == true ? "found, not enabled" : "not found"
    }
}

extension Config {
    public func appRows(facts: any SystemFacts) -> [AppRow] {
        allApps.map { app in
            let bundleID = app.installedBundleID(facts: facts)
            return AppRow(id: app.id, name: app.name, role: app.role.rawValue, installed: bundleID != nil, bundleID: bundleID)
        }
    }

    /// - Parameter found: The commands the login shell found among those of the agents, or `nil` when nobody asked it.
    public func agentRows(found: Set<String>? = nil) -> [AgentRow] {
        allAgents.map { agent in
            AgentRow(
                id: agent.id, name: agent.name, command: agent.command,
                enabled: enabledAgents.contains(agent.id),
                foundInShell: found.map { $0.contains(agent.executable) },
                variants: agent.variants.map(\.id), terminalLink: agent.terminalLink != nil, desktopLink: agent.desktopLink != nil,
                promptArgument: agent.promptArgument?.configValue,
                bypassPermissionArgument: agent.bypassPermissionArgument,
                bypassPermissions: launchOptions(for: agent).bypassFlag != nil
            )
        }
    }
}
