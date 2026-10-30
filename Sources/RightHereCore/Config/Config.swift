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
        /// The config defines templates of its own, which replace the built-in ones (that is not the same as the list being different: this machine may turn one of the built-in ones off).
        public var definesTemplates: Bool
        /// The ids of the templates the New File submenu leaves out (`new_file.hidden`); each is still an action of its own.
        public var hidden: [String]
        /// The config writes `new_file.hidden` (an empty list is a list).
        public var writesHidden = false

        public init(templates: [NewFileTemplate] = NewFileTemplate.builtIn, then: AfterNewFile = .reveal, definesTemplates: Bool = false, hidden: [String] = []) {
            self.templates = templates
            self.then = then
            self.definesTemplates = definesTemplates
            self.hidden = hidden
        }

        /// The templates the New File submenu offers.
        public var shownTemplates: [NewFileTemplate] { templates.filter { !hidden.contains($0.id) } }
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
    /// The language of the Finder menu, the window, the alerts and the names of the Quick Actions: a code of `Localizer.supportedLanguages`; `nil` follows macOS.
    public var language: String?

    /// What the person reads: the config's language, or the system's.
    public var localizer: Localizer { .preferring(language) }
    public var newFile: NewFileSettings
    /// Agents offered in the menu, in order. Empty until `rh setup` finds the installed ones.
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
    /// The built-in agents this machine's `disabled` turns off: they are not in the menu, and a preset that names one is left out.
    public var disabledAgents: Set<String>
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
        disabledAgents: Set<String> = [],
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
        self.disabledAgents = disabledAgents
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
        return agent
    }

    /// What starting an agent adds to what its `command` and a variant say. It is kept apart from the command on purpose: the command is what
    /// the config says the agent is, and these two are what the person asked for this machine: the flag that switches the agent's own
    /// permission prompts off, and `args`.
    public struct AgentLaunchOptions: Sendable, Equatable {
        /// Typed after the command when the agent's permission prompts are switched off (`general.bypass_permissions`, `[agent.<id>]
        /// bypass_permissions`); `nil` when they are on, when the agent has no such flag, or when the command already carries it.
        public var bypassFlag: String?
        /// The person's `[agent.<id>] args`, one argument each.
        public var arguments: [String]

        public static let none = AgentLaunchOptions(bypassFlag: nil, arguments: [])
    }

    public func launchOptions(for agent: AgentDescriptor) -> AgentLaunchOptions {
        let settings = agents[agent.id]
        var flag: String?
        if settings?.bypassPermissions ?? bypassPermissions, let configured = agent.bypassPermissionArgument, !configured.isEmpty {
            let commandWords = Set(agent.command.split(separator: " "))
            flag = configured.split(separator: " ").allSatisfy(commandWords.contains) ? nil : configured
        }
        return AgentLaunchOptions(bypassFlag: flag, arguments: settings?.args ?? [])
    }

    /// The flag that switches an agent's permission prompts off, when what is typed to start `agent` already carries it: in its command (read as a shell reads it, so a quoted flag, one in `$'…'`, or
    /// one that a redirection is written against is the flag), in the arguments the person gave it, or as the flag that carries a first prompt. A start then has no prompts whatever the settings say,
    /// which a preset must not do.
    ///
    /// The flags that count are the agent's own (the built-in one, and the one this config gives it, which can be blanked) and those of the built-in agent whose program the command mentions, whatever
    /// stands in front of it (`FOO=1 claude`, `env claude`, `exec claude`, `Claude`): an agent of one's own that runs `claude --dangerously-skip-permissions` is one that asks nothing, and one that
    /// runs a tool of its own with an `--auto` of its own is not. A flag is its words next to each other and in order, and `--flag=value` and `--flag value` are the same. Another spelling of the same
    /// switch in a tool that has several (`--permission-mode bypassPermissions`) is not known here: the guard is as good as the list of flags that `rh agents` shows. What a line makes the shell
    /// compute (`$x`, `$(…)`, `{a,b}`) cannot be read: `commandHidesBypassFlag(of:)` says so, and a preset refuses such an agent.
    public func bypassFlagTyped(by agent: AgentDescriptor) -> String? {
        var typed = ShellWords.split(agent.command) + (agents[agent.id]?.args ?? [])
        if case .flag(let flag)? = agent.promptArgument { typed.append(flag) }
        return bypassFlags(toLookForIn: agent).first { ShellWords.carries(typed, flag: $0) }
    }

    /// The flag that makes a plain start of the agent skip its permission prompts: the one the switch adds, or one that its command, its arguments or its first-prompt flag types. What the
    /// listings say (`rh agents`, `rh doctor`, `rh menu --explain`).
    public func flagThatSkipsPrompts(for agent: AgentDescriptor) -> String? {
        launchOptions(for: agent).bypassFlag ?? bypassFlagTyped(by: agent)
    }

    /// The flag that a typed line of the agent carries: what a start of it, a start option's included, is told by `rh run`.
    public func bypassFlag(inTypedLine line: String, of agent: AgentDescriptor) -> String? {
        let words = ShellWords.split(line)
        return bypassFlags(toLookForIn: agent).first { ShellWords.carries(words, flag: $0) }
    }

    /// The same, for every start of the agent: the plain one and each of its start options, whose arguments are typed after the command.
    public func bypassFlagTypedAnywhere(by agent: AgentDescriptor) -> String? {
        if let flag = bypassFlagTyped(by: agent) { return flag }
        let flags = bypassFlags(toLookForIn: agent)
        for variant in agent.variants {
            if let flag = flags.first(where: { ShellWords.carries(variant.arguments, flag: $0) }) { return flag }
        }
        return nil
    }

    /// Whether the command of `agent`, which is typed as it is written, has syntax whose result depends on something that is not in it (a parameter, a command, a brace expansion, a quote that is
    /// never closed): the flag that switches the prompts off may be behind it, and nothing here can tell.
    public func commandHidesBypassFlag(of agent: AgentDescriptor) -> Bool {
        ShellWords.hasExpansion(agent.command)
    }

    private func bypassFlags(toLookForIn agent: AgentDescriptor) -> [String] {
        let mentioned = ShellWords.programNames(in: ShellWords.split(agent.command))
        let ofTheProgram = KnownAgents.all.filter { known in
            ShellWords.split(known.command).first.map { mentioned.contains(($0 as NSString).lastPathComponent.lowercased()) } ?? false
        }.map(\.bypassPermissionArgument)
        var flags: [String] = []
        for flag in [agent.bypassPermissionArgument, KnownAgents.agent(id: agent.id)?.bypassPermissionArgument] + ofTheProgram {
            if let flag, !flag.isEmpty, !flags.contains(flag) { flags.append(flag) }
        }
        return flags
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
