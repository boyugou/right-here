import Foundation

/// The settings that shape what Right Here offers and how actions run.
public struct Config: Sendable, Equatable {
    public enum AfterNewFile: String, Sendable, Codable, CaseIterable {
        /// Select the new file in Finder so Return renames it.
        case reveal
        /// Open the new file in the default editor.
        case open
        case nothing
    }

    public struct NewFileSettings: Sendable, Equatable {
        public var templates: [NewFileTemplate]
        public var then: AfterNewFile

        public init(templates: [NewFileTemplate] = NewFileTemplate.builtIn, then: AfterNewFile = .reveal) {
            self.templates = templates
            self.then = then
        }
    }

    public struct AgentSettings: Sendable, Equatable {
        /// How the agent starts when an action does not name a launcher; `nil` types it into the default terminal.
        public var launcher: AgentLauncher?
        /// Replaces the descriptor's command, for example `claude --model opus`.
        public var command: String?
        /// Variants added to the built-in ones.
        public var variants: [AgentDescriptor.Variant]

        public init(launcher: AgentLauncher? = nil, command: String? = nil, variants: [AgentDescriptor.Variant] = []) {
            self.launcher = launcher
            self.command = command
            self.variants = variants
        }
    }

    /// Default terminal id; `nil` picks the first installed one.
    public var terminal: String?
    /// Default editor id; `nil` picks the first installed one.
    public var editor: String?
    public var newFile: NewFileSettings
    /// Settings per agent id. Agents that are absent use their built-in descriptor.
    public var agents: [String: AgentSettings]
    /// Applications added by the user, alongside the built-in ones.
    public var apps: [AppDescriptor]
    /// Custom agents added by the user.
    public var customAgents: [AgentDescriptor]

    public init(
        terminal: String? = nil,
        editor: String? = nil,
        newFile: NewFileSettings = NewFileSettings(),
        agents: [String: AgentSettings] = [:],
        apps: [AppDescriptor] = [],
        customAgents: [AgentDescriptor] = []
    ) {
        self.terminal = terminal
        self.editor = editor
        self.newFile = newFile
        self.agents = agents
        self.apps = apps
        self.customAgents = customAgents
    }

    public static let `default` = Config()

    public func app(id: String) -> AppDescriptor? {
        apps.first { $0.id == id } ?? KnownApps.app(id: id)
    }

    public func agent(id: String) -> AgentDescriptor? {
        guard var agent = customAgents.first(where: { $0.id == id }) ?? KnownAgents.agent(id: id) else { return nil }
        if let settings = agents[id] {
            if let command = settings.command { agent.command = command }
            agent.variants += settings.variants
        }
        return agent
    }
}
