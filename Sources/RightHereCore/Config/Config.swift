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
        /// Replaces how the command takes a first prompt (see `AgentPreset`).
        public var promptArgument: PromptArgument?
        /// Whether to bypass tool permission / confirmation prompts. `nil` inherits general.bypass_permissions.
        public var bypassPermissions: Bool?
        /// Custom argument or flag to bypass permission confirmations for this agent.
        public var bypassPermissionArgument: String?
        /// Additional arguments to pass when launching this agent.
        public var args: [String]

        public init(
            launcher: AgentLauncher? = nil,
            command: String? = nil,
            variants: [AgentDescriptor.Variant] = [],
            promptArgument: PromptArgument? = nil,
            bypassPermissions: Bool? = nil,
            bypassPermissionArgument: String? = nil,
            args: [String] = []
        ) {
            self.launcher = launcher
            self.command = command
            self.variants = variants
            self.promptArgument = promptArgument
            self.bypassPermissions = bypassPermissions
            self.bypassPermissionArgument = bypassPermissionArgument
            self.args = args
        }
    }

    /// Default terminal id; `nil` picks the first installed one.
    public var terminal: String?
    /// Default editor id; `nil` picks the first installed one.
    public var editor: String?
    /// Whether a terminal session starts in a new window or a new tab of the front one (Ghostty only).
    public var terminalPlacement: TerminalPlacement
    public var newFile: NewFileSettings
    /// Agents offered in the menu, in order. Empty until `rh init` detects the installed ones.
    public var enabledAgents: [String]
    /// The entries of the Finder menu, in order; `nil` means the default layout.
    public var menuItems: [String]?
    /// The forms offered under "Copy Path".
    public var copyPathStyles: [PathStyle]
    /// Custom menu title for "Copy Path" action or submenu; `nil` uses the localized default.
    public var copyPathTitle: String?
    /// Action ids offered as Finder Services (Quick Actions); `nil` means the default set.
    public var serviceItems: [String]?
    /// Settings per agent id. Agents that are absent use their built-in descriptor.
    public var agents: [String: AgentSettings]
    /// Whether to launch AI agents with bypass permissions / autonomous flags.
    public var bypassPermissions: Bool
    /// Applications added by the user, alongside the built-in ones.
    public var apps: [AppDescriptor]
    /// Built-in applications the per-machine overlay removed with `disabled`: they are neither offered nor found by id.
    public var disabledApps: Set<String>
    /// Custom agents added by the user.
    public var customAgents: [AgentDescriptor]
    /// Prompt presets: the built-in ones, with those the config redefines replaced in place, then the config's own.
    public var presets: [AgentPreset]

    public init(
        terminal: String? = nil,
        editor: String? = nil,
        terminalPlacement: TerminalPlacement = .newWindow,
        newFile: NewFileSettings = NewFileSettings(),
        enabledAgents: [String] = [],
        menuItems: [String]? = nil,
        copyPathStyles: [PathStyle] = Config.defaultCopyPathStyles,
        copyPathTitle: String? = nil,
        serviceItems: [String]? = nil,
        agents: [String: AgentSettings] = [:],
        apps: [AppDescriptor] = [],
        disabledApps: Set<String> = [],
        customAgents: [AgentDescriptor] = [],
        presets: [AgentPreset] = AgentPreset.builtIn,
        bypassPermissions: Bool = false
    ) {
        self.terminal = terminal
        self.editor = editor
        self.terminalPlacement = terminalPlacement
        self.newFile = newFile
        self.enabledAgents = enabledAgents
        self.menuItems = menuItems
        self.copyPathStyles = copyPathStyles
        self.copyPathTitle = copyPathTitle
        self.serviceItems = serviceItems
        self.agents = agents
        self.apps = apps
        self.disabledApps = disabledApps
        self.customAgents = customAgents
        self.presets = presets
        self.bypassPermissions = bypassPermissions
    }

    public static let `default` = Config()

    public static let defaultCopyPathStyles: [PathStyle] = [.absolute, .tilde, .gitRelative, .name, .shellEscaped, .aiMention]

    public func app(id: String) -> AppDescriptor? {
        apps.first { $0.id == id } ?? (disabledApps.contains(id) ? nil : KnownApps.app(id: id))
    }

    /// The terminal with this id; `nil` when no app has it or it is not a terminal (a built-in id can be redefined as
    /// an editor).
    public func terminalApp(id: String) -> AppDescriptor? {
        app(id: id).flatMap { $0.role == .terminal ? $0 : nil }
    }

    /// Every app Right Here offers: the ones the config defines, then the built-in ones they do not
    /// replace. An app defined under a built-in id replaces that built-in everywhere.
    public var allApps: [AppDescriptor] {
        let replaced = Set(apps.map(\.id))
        return apps + KnownApps.all.filter { !replaced.contains($0.id) && !disabledApps.contains($0.id) }
    }

    /// How an agent action starts. Variants are command-line options typed into a shell, so an action with
    /// a variant always types, even when the agent's default launcher is its deep link or desktop app;
    /// naming such a launcher together with a variant has no meaning and is reported as `conflict`.
    public func launcher(forAgent id: String, explicit: AgentLauncher?, hasVariant: Bool) -> (launcher: AgentLauncher, conflict: String?) {
        let wanted = explicit ?? agents[id]?.launcher ?? .terminal(nil)
        guard hasVariant else { return (wanted, nil) }
        if case .terminal = wanted { return (wanted, nil) }
        let conflict = explicit.map { _ in
            "A variant adds command-line options, so it can only start in a terminal, not through \(wanted == .desktop ? "the desktop app" : "the agent's own terminal link")."
        }
        return (.terminal(nil), conflict)
    }

    /// Every agent Right Here offers, as the config shapes it: the ones the config defines, then the built-in ones.
    public var allAgents: [AgentDescriptor] {
        (customAgents + KnownAgents.all).compactMap { agent(id: $0.id) }
    }

    public func agent(id: String) -> AgentDescriptor? {
        guard var agent = customAgents.first(where: { $0.id == id }) ?? KnownAgents.agent(id: id) else { return nil }
        let settings = agents[id]
        if let settings {
            if let command = settings.command { agent.command = command }
            agent.variants += settings.variants
            if let promptArgument = settings.promptArgument { agent.promptArgument = promptArgument }
            if let bypassArg = settings.bypassPermissionArgument { agent.bypassPermissionArgument = bypassArg }
        }

        let shouldBypass = settings?.bypassPermissions ?? bypassPermissions
        if shouldBypass, let flag = agent.bypassPermissionArgument, !flag.isEmpty {
            let flagWords = flag.split(separator: " ").map(String.init)
            let cmdWords = agent.command.split(separator: " ").map(String.init)
            let alreadyPresent = flagWords.allSatisfy { cmdWords.contains($0) }
            if !alreadyPresent {
                agent.command += " \(flag)"
            }
        }

        if let extraArgs = settings?.args, !extraArgs.isEmpty {
            for arg in extraArgs {
                agent.command += " \(ShellQuoting.quote(arg, for: .posix))"
            }
        }

        return agent
    }

    public func preset(id: String) -> AgentPreset? {
        presets.first { $0.id == id }
    }

    /// The agent a preset runs with: the one it names, else the first one in `general.agents`.
    public func agent(for preset: AgentPreset) -> AgentDescriptor? {
        (preset.agent ?? enabledAgents.first).flatMap { agent(id: $0) }
    }

    /// Why a preset's agent cannot be given its prompt, or `nil`.
    func presetAgentRefusal(_ preset: AgentPreset) -> String? {
        guard let agent = agent(for: preset) else {
            return preset.agent.map { "Unknown agent \"\($0)\"." } ?? "No agent is enabled; list one in general.agents, or name an agent in the preset."
        }
        if agent.promptArgument == nil { return "\(agent.name) is not known to take a first prompt. Set prompt_arg in [agent.\(agent.id)] (\"positional\" or a flag such as \"--prompt\")." }
        return nil
    }
}
