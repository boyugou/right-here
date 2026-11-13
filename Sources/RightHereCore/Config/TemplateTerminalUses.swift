import Foundation

extension Config {
    /// One place where a click is made to start through the command template of an app that the config defines (`open_args`, `run_args`: a program of its own).
    public struct TemplateTerminalUse: Sendable, Equatable {
        /// Where the config makes the choice, in config terms: `[general] terminal`, `[agent.claude] terminal`, an item of the menu or of the Quick Actions.
        public var place: String
        /// The terminal it chooses.
        public var terminal: String
        /// What that terminal starts, as one text, so that a terminal that is another program under the same id is another use.
        public var program: String
    }

    /// Where the config chooses a terminal that starts through a command template: the default terminal, the terminal an agent is given, and an item of the menu or of the Quick Actions that names
    /// one (`open.terminal@remote`, `agent.claude@remote`, `preset.review@remote`). Choosing such a terminal is choosing a program, whichever of these says it, and which program an id means can
    /// change without the choice changing (an app that takes the id of another).
    /// What the app with this id starts through its command template, as one text; `nil` for an app without one (or no app).
    public func templateProgram(of id: String) -> String? {
        guard let app = app(id: id), case .template(let launch) = app.driver else { return nil }
        return [launch.open, launch.run].map { $0.map { "[" + $0.joined(separator: "\u{1F}") + "]" } ?? "-" }.joined(separator: "\u{1E}") + "\u{1D}" + app.bundleIDs.joined(separator: "\u{1F}")
    }

    /// The items of the menu and of the Quick Actions that start an agent through its link or its desktop app (`agent.codex@desktop`, `agent.claude@link`): for a
    /// click on such an item they do what `[agent.<id>] launcher` does for every start, and leave out the agent's command and arguments.
    public var agentItemsWithoutTheirCommand: Set<String> {
        Set(((menuItems ?? []) + (serviceItems ?? [])).filter { item in
            guard case .agent(_, _, let launcher)? = ActionRef(parsing: item) else { return false }
            return ConfigTrust.route(launcher) != AgentLauncher.terminalWord
        })
    }

    /// The terminals a click falls back to, in the order they are tried, that start through a command template: with no default terminal, or one that is not
    /// installed, the first installed terminal is used, and that can be one of these although no setting names it.
    public var templateTerminalsToFallBackTo: [String] {
        DefaultApps.candidates(in: self, role: .terminal).map(\.id).filter { templateProgram(of: $0) != nil }
    }

    public var templateTerminalUses: [TemplateTerminalUse] {
        func program(of id: String?) -> (id: String, program: String)? {
            guard let id, let program = templateProgram(of: id) else { return nil }
            return (id, program)
        }
        var uses: [TemplateTerminalUse] = []
        if let found = program(of: terminal) { uses.append(TemplateTerminalUse(place: "[general] terminal", terminal: found.id, program: found.program)) }
        for (id, settings) in agents.sorted(by: { $0.key < $1.key }) {
            if case .terminal(let chosen)? = settings.launcher, let found = program(of: chosen) {
                uses.append(TemplateTerminalUse(place: "[agent.\(id)] terminal", terminal: found.id, program: found.program))
            }
        }
        for item in (menuItems ?? []) + (serviceItems ?? []) {
            var chosen: String?
            switch ActionRef(parsing: item) {
            case .openTerminal(let terminal)?: chosen = terminal
            case .agent(_, _, let launcher)?: if case .terminal(let terminal)? = launcher { chosen = terminal }
            case .preset(_, let terminal)?: chosen = terminal
            default: break
            }
            if let found = program(of: chosen), !uses.contains(where: { $0.place == "an item of the menu or of the Quick Actions: \(item)" }) {
                uses.append(TemplateTerminalUse(place: "an item of the menu or of the Quick Actions: \(item)", terminal: found.id, program: found.program))
            }
        }
        return uses
    }
}
