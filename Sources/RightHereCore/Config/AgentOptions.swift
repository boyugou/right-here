import Foundation

/// One agent's own settings as something to edit in the window (ADR 0026): the `[agent.<id>]` table. Its command, how it starts and in which terminal, whether its permission prompts are on, and
/// the arguments it is given. A pure function of the config and what is installed; the changes it returns are applied through `ConfigService`.
public struct AgentOptionsState: Sendable, Equatable, Identifiable {
    /// How an agent starts: typed into a terminal, through its own terminal link, or through its desktop app.
    public enum Launcher: String, Sendable, Equatable, CaseIterable {
        case terminal, link, desktop
    }

    public var id: String
    /// The name it has in the menu. Only an agent the config defines has a name of its own: a built-in one is called what it is called.
    public var name: String
    public var isBuiltIn: Bool
    /// What is typed to start it, as the config says (the built-in command when it says nothing).
    public var command: String
    /// The command of the built-in agent of this id; `nil` for one the config defines.
    public var builtInCommand: String?
    public var launcher: Launcher
    /// The ways this agent can start: every agent in a terminal, and those that have a terminal link or a desktop app also that.
    public var launchers: [Launcher]
    /// The terminal it is typed into (`terminal`), `nil` for the default one.
    public var terminal: String?
    /// The terminals that can run a command, and the one chosen when it is not one of them (not installed, or one that only opens folders), as it is.
    public var terminals: [GeneralSettingsState.App]
    /// The terminal the agent is typed into when it names none: the default one when it is installed, else the first that can run a command (`DefaultApps.commandTerminal`); `nil` when no terminal is installed.
    public var automaticTerminal: GeneralSettingsState.App?
    /// Its own `bypass_permissions`, which beats the general switch; `nil` follows it.
    public var bypassOverride: Bool?
    /// The flag its own `bypass_permission_arg` gives, and the one the agent has built in.
    public var bypassArgument: String?
    public var builtInBypassArgument: String?
    /// `args`, as the config has them.
    public var args: [String]
    /// What the file that decides `agent.<id>.args` writes for it (`nil`: nothing); changes of the list are made on condition that it still says this.
    public var listedArgs: [String]?
    /// Its own `prompt_arg`, the word the config spells (`positional`, or a flag such as `-i`); `nil` when the config says nothing.
    public var promptArgument: String?
    /// The `prompt_arg` the agent has built in, in the same words.
    public var builtInPromptArgument: String?
    /// The start options that the config writes, as pages to edit, and the others, to show (the agent's built-in ones).
    public var variants: [VariantRowState] = []
    public var fixedVariants: [FixedVariant] = []

    /// The arguments as a list to edit.
    public var argumentList: ArgumentList { ArgumentList(key: AgentOptions.argumentsKey(of: id), items: args, listed: listedArgs) }

    /// Whether the arguments are the items of that file's list one for one.
    public var argsAreExact: Bool { argumentList.isExact }
}

public enum AgentOptions {
    private static func key(_ agent: String, _ setting: String) -> String { "agent.\(agent).\(setting)" }

    /// The key of the list of an agent's arguments, which `ConfigService.listed` reads for `AgentOptionsState.listedArgs`.
    public static func argumentsKey(of agent: String) -> String { key(agent, "args") }

    /// The options of the agent `id`; `nil` when no agent has it.
    /// - Parameter listedArgs: what the file that decides `agent.<id>.args` writes for it (`ConfigService.listed`).
    /// - Parameters:
    ///   - variantEntries: Where each start option the config writes for this agent is (`ConfigService.entryLocations(of: "agent.<id>.variant")`).
    ///   - listedVariantArguments: What the file that holds each of them writes for its `arguments`, by the id of the entry.
    public static func state(id: String, config: Config, facts: any SystemFacts, listedArgs: [String]?, variantEntries: [String: EntryLocation] = [:],
                             listedVariantArguments: [String: [String]] = [:]) -> AgentOptionsState? {
        guard let agent = config.agent(id: id) else { return nil }
        let builtIn = KnownAgents.agent(id: id)
        let settings = config.agents[id]
        var launcher = AgentOptionsState.Launcher.terminal
        var terminal: String?
        switch settings?.launcher ?? .terminal(nil) {
        case .terminal(let chosen): terminal = chosen
        case .terminalLink: launcher = .link
        case .desktop: launcher = .desktop
        }
        var launchers: [AgentOptionsState.Launcher] = [.terminal]
        if agent.terminalLink != nil { launchers.append(.link) }
        if agent.desktopLink != nil { launchers.append(.desktop) }
        var terminals = GeneralSettings.state(config: config, facts: facts, listedAgents: nil).terminals.filter(\.runsCommands)
        if let terminal, !terminals.contains(where: { $0.id == terminal }), let app = config.terminalApp(id: terminal) {
            let bundleID = app.installedBundleID(facts: facts)
            terminals.append(GeneralSettingsState.App(id: app.id, name: app.name, icon: (bundleID ?? app.bundleIDs.first).map(Icon.app), installed: bundleID != nil,
                                                      runsCommands: TerminalAdapters.adapter(for: app).supportsCommands))
        }
        let automatic = (try? DefaultApps(config: config, facts: facts).commandTerminal()).map { app -> GeneralSettingsState.App in
            let bundleID = app.installedBundleID(facts: facts)
            return GeneralSettingsState.App(id: app.id, name: app.name, icon: (bundleID ?? app.bundleIDs.first).map(Icon.app), installed: bundleID != nil, runsCommands: TerminalAdapters.adapter(for: app).supportsCommands)
        }
        let variants = AgentVariants.variants(of: id, config: config, entries: variantEntries, listed: listedVariantArguments)
        return AgentOptionsState(id: id, name: agent.name, isBuiltIn: builtIn != nil, command: agent.command, builtInCommand: builtIn?.command, launcher: launcher, launchers: launchers,
                                 terminal: terminal, terminals: terminals, automaticTerminal: automatic, bypassOverride: settings?.bypassPermissions, bypassArgument: settings?.bypassPermissionArgument,
                                 builtInBypassArgument: builtIn?.bypassPermissionArgument, args: settings?.args ?? [], listedArgs: listedArgs, promptArgument: settings?.promptArgument?.configValue,
                                 builtInPromptArgument: builtIn?.promptArgument?.configValue, variants: variants.own, fixedVariants: variants.fixed)
    }

    // MARK: The changes

    /// Its name, for an agent the config defines.
    public static func operations(settingName name: String, of agent: AgentOptionsState) -> [ConfigOperation] {
        let text = name.trimmingCharacters(in: .whitespaces)
        guard !agent.isBuiltIn, !text.isEmpty, text != agent.name else { return [] }
        return [.set(key(agent.id, "name"), .string(text))]
    }

    /// What is typed to start it. A built-in agent's own command is the setting taken out, so that a better one in a later version reaches it.
    public static func operations(settingCommand command: String, of agent: AgentOptionsState) -> [ConfigOperation] {
        let text = command.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text != agent.command else { return [] }
        if text == agent.builtInCommand { return [.unset(key(agent.id, "command"))] }
        return [.set(key(agent.id, "command"), .string(text))]
    }

    /// How it starts. In a terminal is what an agent does when nothing is said, so that is the setting taken out.
    public static func operations(settingLauncher launcher: AgentOptionsState.Launcher, of agent: AgentOptionsState) -> [ConfigOperation] {
        guard launcher != agent.launcher, agent.launchers.contains(launcher) else { return [] }
        return launcher == .terminal ? [.unset(key(agent.id, "launcher"))] : [.set(key(agent.id, "launcher"), .string(launcher.rawValue))]
    }

    /// The terminal it is typed into; `nil` is the default terminal.
    public static func operations(settingTerminal terminal: String?, of agent: AgentOptionsState) -> [ConfigOperation] {
        guard terminal != agent.terminal else { return [] }
        return terminal.map { [.set(key(agent.id, "terminal"), .string($0))] } ?? [.unset(key(agent.id, "terminal"))]
    }

    /// Whether its permission prompts are switched off: yes, no, or as the general switch says (`nil`).
    public static func operations(settingBypass override: Bool?, of agent: AgentOptionsState) -> [ConfigOperation] {
        guard override != agent.bypassOverride else { return [] }
        return override.map { [.set(key(agent.id, "bypass_permissions"), .boolean($0))] } ?? [.unset(key(agent.id, "bypass_permissions"))]
    }

    /// The flag that switches its prompts off, when it is not the one it has built in (or has none). Empty, and the built-in flag typed out, are the setting taken out, as the command is: the
    /// agent then follows a better flag of a later version.
    public static func operations(settingBypassArgument argument: String, of agent: AgentOptionsState) -> [ConfigOperation] {
        let text = argument.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || text == agent.builtInBypassArgument { return agent.bypassArgument == nil ? [] : [.unset(key(agent.id, "bypass_permission_arg"))] }
        guard text != agent.bypassArgument else { return [] }
        return [.set(key(agent.id, "bypass_permission_arg"), .string(text))]
    }

    /// An argument at the end of the list.
    public static func operations(addingArgument argument: String, to agent: AgentOptionsState) -> [ConfigOperation] {
        agent.argumentList.adding(argument)
    }

    /// The argument at `position` (from 1) taken out.
    public static func operations(removingArgumentAt position: Int, of agent: AgentOptionsState) -> [ConfigOperation] {
        agent.argumentList.removing(at: position)
    }

    /// The argument at `position` (from 1) written another way, in its place and with its comments (`ArgumentList.setting`).
    public static func operations(settingArgumentAt position: Int, to argument: String, of agent: AgentOptionsState, expecting shown: String? = nil) -> [ConfigOperation] {
        agent.argumentList.setting(at: position, to: argument, expecting: shown)
    }

    /// What a drag in the list of arguments says (SwiftUI's `onMove`, counting from 0).
    public static func operations(movingArguments source: IndexSet, to destination: Int, of agent: AgentOptionsState) -> [ConfigOperation] {
        agent.argumentList.moving(source, to: destination)
    }

    /// How the command takes a first prompt, which prompt presets need: `positional`, or the flag that carries it. The built-in way, or none, is the setting taken out, so that a better one in a
    /// later version reaches the agent; the config refuses a word that is neither `positional` nor a flag.
    public static func operations(settingPromptArgument word: String, of agent: AgentOptionsState) -> [ConfigOperation] {
        let text = word.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || text == agent.builtInPromptArgument { return agent.promptArgument == nil ? [] : [.unset(key(agent.id, "prompt_arg"))] }
        guard text != agent.promptArgument else { return [] }
        return [.set(key(agent.id, "prompt_arg"), .string(text))]
    }

    // MARK: An agent of one's own

    static let maxIdentifierLength = IDSlug.maxLength

    /// The id an agent of this name would have: lowercase letters and digits, joined by dashes, and not one that another agent has. `nil` for a name without a letter or a digit.
    public static func identifier(for name: String, taken: Set<String>) -> String? {
        IDSlug.make(from: name).map { slug in IDSlug.unique(slug) { taken.contains($0) || KnownAgents.agent(id: $0) != nil } }
    }

    /// What taking an agent of one's own out comes to: its entry in the list of the menu first (a list that names an agent nobody defines does not read), then its table. Two groups, because
    /// the list and the table can be in different files, and each group is made in its own.
    public struct Removal: Sendable, Equatable {
        public var list: [ConfigOperation]
        public var table: [ConfigOperation]
        /// Whether the menu lists the agent at all.
        public var isListed: Bool
        public var all: [ConfigOperation] { list + table }
    }

    /// An agent of one's own taken out. `nil` for a built-in agent, which is not in the config, and for a list that is not the one that is shown.
    public static func operations(removing agent: AgentOptionsState, in general: GeneralSettingsState) -> Removal? {
        guard !agent.isBuiltIn, general.agentsAreExact, general.agents.contains(where: { $0.id == agent.id }) else { return nil }
        var list: [ConfigOperation] = [.expect(general.listedAgents, in: GeneralSettingsState.agentsKey)]
        let place = general.listedAgents?.firstIndex(of: agent.id)
        if let place { list.append(.remove(at: place + 1, from: GeneralSettingsState.agentsKey)) }
        return Removal(list: list, table: [.removeTable("agent.\(agent.id)")], isListed: place != nil)
    }

    /// The id of a new agent: made from its name, and when the name has no letter or digit that an id can hold (「ラザギット」) from the program it starts, and else `agent`.
    static func newIdentifier(name: String, command: String, taken: Set<String>) -> String {
        let first = command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let program = first.split(separator: "/").last.map(String.init) ?? first
        return identifier(for: name, taken: taken) ?? identifier(for: program, taken: taken) ?? identifier(for: "agent", taken: taken) ?? "agent"
    }

    /// A new agent, defined with its name and its command and put in the menu after the ones that are there. The id is made from the name.
    /// - Parameter alsoTaken: Ids that the files mention and the config does not show (`ConfigService.agentIDsInUse`): an agent that this Mac turns off, a table the other file makes.
    public static func operations(creating name: String, command: String, in general: GeneralSettingsState, alsoTaken: Set<String> = []) -> (id: String, operations: [ConfigOperation])? {
        let title = name.trimmingCharacters(in: .whitespaces), typed = command.trimmingCharacters(in: .whitespaces)
        guard general.agentsAreExact, !title.isEmpty, !typed.isEmpty else { return nil }
        let id = newIdentifier(name: title, command: typed, taken: Set(general.agents.map(\.id)).union(alsoTaken))
        return (id, [.expect(general.listedAgents, in: GeneralSettingsState.agentsKey),
                     .addTable("agent.\(id)", fields: [ConfigField("name", .string(title)), ConfigField("command", .string(typed))]),
                     .insert(id, into: GeneralSettingsState.agentsKey, at: nil)])
    }
}
