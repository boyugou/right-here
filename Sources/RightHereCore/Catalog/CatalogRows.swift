import Foundation

/// One application as `rh apps` and the MCP catalog tool list it.
public struct AppRow: Sendable, Equatable, Encodable {
    public var id: String
    public var name: String
    public var role: String
    public var installed: Bool
    public var bundleID: String?
}

/// One agent as `rh agents` and the MCP catalog tool list it. Whether the command is found in the login shell
/// is not part of it: that takes a shell, which only `rh agents` starts.
public struct AgentRow: Sendable, Equatable, Encodable {
    public var id: String
    public var name: String
    public var command: String
    public var enabled: Bool
    public var variants: [String]
    public var terminalLink: Bool
    public var desktopLink: Bool
}

extension Config {
    public func appRows(facts: any SystemFacts) -> [AppRow] {
        allApps.map { app in
            let bundleID = app.installedBundleID(facts: facts)
            return AppRow(id: app.id, name: app.name, role: app.role.rawValue, installed: bundleID != nil, bundleID: bundleID)
        }
    }

    public var agentRows: [AgentRow] {
        allAgents.map { agent in
            AgentRow(
                id: agent.id, name: agent.name, command: agent.command,
                enabled: enabledAgents.contains(agent.id),
                variants: agent.variants.map(\.id), terminalLink: agent.terminalLink != nil, desktopLink: agent.desktopLink != nil
            )
        }
    }
}
