import Foundation

/// The settings of `[general]` as something to edit in the window (ADR 0026): which terminal and editor open things, where a terminal session starts, whether agents start without
/// asking, and which agents the menu offers and in what order. A pure function of the config and what is installed; the changes it returns are applied through `ConfigService`.
public struct GeneralSettingsState: Sendable, Equatable {
    /// A terminal or an editor the person can choose.
    public struct App: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var icon: Icon?
        public var installed: Bool
        /// Whether a command can be typed into a new session of it, which an agent needs. An editor is not asked.
        public var runsCommands: Bool
    }

    /// An agent, in the list of the ones the menu offers or among those it does not.
    public struct Agent: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        /// What is typed to start it, as written (`claude`, `claude --model opus`).
        public var command: String
        /// The program `command` starts, which a terminal's login shell has to find (`AgentDescriptor.executable`).
        public var executable: String
        /// Where the agent says how to install it, for a built-in one (`AgentDescriptor.installPage`).
        public var installPage: URL?
        public var icon: Icon?
        public var enabled: Bool
        /// What `bypass_permissions` adds to this agent's command, as written; `nil` when no flag is known for it (its `bypass_permission_arg` would have to say).
        public var bypassFlag: String?
        /// The agent's own `bypass_permissions`, which beats the general one; `nil`: it follows the general setting.
        public var bypassOverride: Bool?
        /// Whether a click can start it without its being in `general.agents`: an item of the menu or of the Quick Actions names it (`agent.codex`).
        public var offered = false
    }

    /// The terminals that are installed, the one a click would use first; and the configured one when it is not installed (so that the choice shows).
    public var terminals: [App]
    public var editors: [App]
    /// What the config says (`nil`: the first installed one is used).
    public var terminal: String?
    public var editor: String?
    /// What a click uses now.
    public var usedTerminal: String?
    public var usedEditor: String?
    /// Whether the terminal that is used can type a command into a new session (`false`: it only opens a folder, and an agent would be refused there).
    public var usedTerminalRunsCommands: Bool
    public var placement: TerminalPlacement
    /// The places the terminal that is used can start a session in; only a window for most of them.
    public var placements: [TerminalPlacement]

    /// Why the placement the config asks for opens a new window instead, or `nil` when the terminal that is used has it.
    public enum PlacementFallback: Sendable, Equatable {
        /// The terminal has nothing but windows.
        case windowOnly
        /// It has tabs and no splits (Warp), and the config asks for a split.
        case noSplits
    }

    /// Where a session of the terminal that is used opens: the config's placement when the terminal has it, or a new window.
    public var effectivePlacement: TerminalPlacement {
        placements.contains(placement) ? placement : .newWindow
    }

    public var placementFallback: PlacementFallback? {
        guard !placements.contains(placement) else { return nil }
        return placements == [.newWindow] ? .windowOnly : .noSplits
    }

    /// Agents start with the flags that switch their permission prompts off (presets keep them on).
    public var bypassPermissions: Bool
    /// The agents the menu offers, in the order of `general.agents`, and then every other agent Right Here knows.
    public var agents: [Agent]

    /// What the file that decides `general.agents` writes for it (`nil`: it does not write the list). Every change of the list is made on condition that the file still says this.
    public var listedAgents: [String]?

    public var enabledAgents: [Agent] { agents.filter(\.enabled) }

    /// The name of the terminal or the editor that is used when none is configured: the best one that is installed.
    public var automaticTerminalName: String? { terminals.first { $0.installed }?.name }
    public var automaticEditorName: String? { editors.first { $0.installed }?.name }

    /// What the switch that starts agents without asking would do to each agent, for the line under it: the agents a click can start (those of the menu's list, and those an item of the
    /// menu or of the Quick Actions names), or when there are none, every agent there is.
    public var bypassLines: [BypassLine] {
        let started = agents.filter { $0.enabled || $0.offered }
        return (started.isEmpty ? agents : started).map { agent in
            if agent.bypassOverride == false { return BypassLine(agent: agent.name, outcome: .keepsAsking) }
            guard let flag = agent.bypassFlag else { return BypassLine(agent: agent.name, outcome: .noFlag) }
            return BypassLine(agent: agent.name, outcome: .flag(flag))
        }
    }

    /// What the permission switch comes to for one agent.
    public struct BypassLine: Sendable, Equatable {
        public enum Outcome: Sendable, Equatable {
            /// It is started with this flag, and does not ask.
            case flag(String)
            /// It has no flag that switches its prompts off, so it keeps asking.
            case noFlag
            /// Its own setting keeps its prompts on whatever the general switch says.
            case keepsAsking
        }

        public var agent: String
        public var outcome: Outcome
    }

    /// Whether the enabled agents are the items of that file's list one for one. They are not when the list names an agent twice, or when this Mac turns one off (`disabled` in its own
    /// config): a place among the agents is then not a place in the list, and nothing is offered to change by place.
    public var agentsAreExact: Bool { (listedAgents ?? []) == enabledAgents.map(\.id) }

    public static let agentsKey = "general.agents"
}

public enum GeneralSettings {
    /// - Parameter listedAgents: what the file that decides `general.agents` writes for it (`ConfigDocument.elements(of:)`), which the changes of the list are held to.
    public static func state(config: Config, facts: any SystemFacts, listedAgents: [String]?) -> GeneralSettingsState {
        let defaults = DefaultApps(config: config, facts: facts)
        func choices(for role: AppDescriptor.Role, configured: String?) -> [GeneralSettingsState.App] {
            var apps = (DefaultApps.ranked(config.allApps, role: role) + config.apps.filter { $0.role == role && $0.defaultRank == nil })
                .filter { $0.installedBundleID(facts: facts) != nil }
            // The configured app is shown even when it is not installed, so that the choice is not hidden.
            if let configured, !apps.contains(where: { $0.id == configured }), let app = config.app(id: configured), app.role == role { apps.append(app) }
            var seen = Set<String>()
            return apps.filter { seen.insert($0.id).inserted }.map { app in
                let bundleID = app.installedBundleID(facts: facts)
                return GeneralSettingsState.App(id: app.id, name: app.name, icon: (bundleID ?? app.bundleIDs.first).map(Icon.app), installed: bundleID != nil,
                                                runsCommands: role == .editor || TerminalAdapters.adapter(for: app).supportsCommands)
            }
        }
        func icon(of agent: AgentDescriptor) -> Icon {
            agent.iconBundleID.flatMap { facts.applicationURL(bundleID: $0) != nil ? Icon.app($0) : nil } ?? .symbol("terminal")
        }
        let offered = PromptEffects.offeredAgents(config)
        func row(_ agent: AgentDescriptor, enabled: Bool) -> GeneralSettingsState.Agent {
            GeneralSettingsState.Agent(id: agent.id, name: agent.name, command: agent.command, executable: agent.executable, installPage: agent.installPage, icon: icon(of: agent), enabled: enabled, bypassFlag: agent.bypassPermissionArgument.flatMap { $0.isEmpty ? nil : $0 },
                                       bypassOverride: config.agents[agent.id]?.bypassPermissions, offered: offered.contains(agent.id))
        }
        let enabled = config.enabledAgents.compactMap { id in config.agent(id: id) }
        let others = config.allAgents.filter { agent in !config.enabledAgents.contains(agent.id) }
        let usedTerminal = (try? defaults.resolve(role: .terminal, configured: config.terminal))
        let adapter = usedTerminal.map(TerminalAdapters.adapter(for:))
        return GeneralSettingsState(
            terminals: choices(for: .terminal, configured: config.terminal), editors: choices(for: .editor, configured: config.editor),
            terminal: config.terminal, editor: config.editor,
            usedTerminal: usedTerminal?.id,
            usedEditor: (try? defaults.resolve(role: .editor, configured: config.editor))?.id,
            usedTerminalRunsCommands: adapter?.supportsCommands ?? true,
            placement: config.terminalPlacement, placements: adapter?.supportedPlacements ?? [.newWindow], bypassPermissions: config.bypassPermissions,
            agents: enabled.map { row($0, enabled: true) } + others.map { row($0, enabled: false) }, listedAgents: listedAgents)
    }

    // MARK: The changes

    /// The terminal that opens things; `nil` goes back to the first one that is installed.
    public static func operations(settingTerminal id: String?) -> [ConfigOperation] { id.map { [.set("general.terminal", .string($0))] } ?? [.unset("general.terminal")] }

    /// The editor; `nil` goes back to the first one that is installed.
    public static func operations(settingEditor id: String?) -> [ConfigOperation] { id.map { [.set("general.editor", .string($0))] } ?? [.unset("general.editor")] }

    /// The language of what the person reads; `nil` goes back to the system's.
    public static func operations(settingLanguage code: String?) -> [ConfigOperation] { code.map { [.set(languageKey, .string($0))] } ?? [.unset(languageKey)] }

    public static let languageKey = "general.language"

    public static func operations(settingPlacement placement: TerminalPlacement) -> [ConfigOperation] { [.set("general.terminal_placement", .string(placement.configName))] }

    public static func operations(settingBypassPermissions on: Bool) -> [ConfigOperation] { [.set("general.bypass_permissions", .boolean(on))] }

    /// The list as the window showed it: a change by place is made only if the file still says that, and never when its places are not those of the agents shown.
    private static func guarded(_ state: GeneralSettingsState) -> [ConfigOperation] {
        [.expect(state.listedAgents, in: GeneralSettingsState.agentsKey)]
    }

    /// Puts an agent in the menu, after the ones that are there.
    public static func operations(enabling agent: String, in state: GeneralSettingsState) -> [ConfigOperation] {
        guard state.agentsAreExact, state.agents.contains(where: { $0.id == agent && !$0.enabled }) else { return [] }
        return guarded(state) + [.insert(agent, into: GeneralSettingsState.agentsKey, at: nil)]
    }

    /// Takes an agent out of the menu.
    public static func operations(disabling agent: String, in state: GeneralSettingsState) -> [ConfigOperation] {
        guard state.agentsAreExact, let index = state.enabledAgents.firstIndex(where: { $0.id == agent }) else { return [] }
        return guarded(state) + [.remove(at: index + 1, from: GeneralSettingsState.agentsKey)]
    }

    /// What a drag in the list of the enabled agents says (SwiftUI's `onMove`, counting from 0 among the enabled ones).
    public static func operations(movingAgents source: IndexSet, to destination: Int, in state: GeneralSettingsState) -> [ConfigOperation] {
        guard state.agentsAreExact else { return [] }
        let moves = ListMoves.operations(moving: source, to: destination, count: state.enabledAgents.count, key: GeneralSettingsState.agentsKey)
        return moves.isEmpty ? [] : guarded(state) + moves
    }
}
