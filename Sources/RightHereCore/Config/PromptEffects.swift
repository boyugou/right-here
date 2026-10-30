import Foundation

/// Which agents a click can start with their permission prompts switched off, and with which flag (ADR 0026, D5).
///
/// Switching the prompts off is the person's decision, and it is a decision about the agents a click can start: the question that comes before it lists them. A change that adds an agent to that
/// list, or gives one of them a flag, widens what the person said yes to, whatever setting it is made through (`general.agents`, a menu item that names the agent, its own flag), so the
/// person is asked again, or an assistant that proposes it waits.
public enum PromptEffects {
    /// One agent that a click starts without its prompts, with the flag that does it.
    public struct Entry: Sendable, Equatable {
        public var agent: String
        public var name: String
        public var flag: String

        public init(agent: String, name: String, flag: String) {
            self.agent = agent
            self.name = name
            self.flag = flag
        }
    }

    /// The agents a click can start: those in `general.agents`, and those that an item of the menu or of the Quick Actions names by their id (`agent.codex`, `agent.codex.resume`, `agent.codex@link`).
    public static func offeredAgents(_ config: Config) -> Set<String> {
        var ids = Set(config.enabledAgents)
        for item in (config.menuItems ?? MenuBuilder.defaultItems) + (config.serviceItems ?? []) {
            if case .agent(let id, _, _)? = ActionRef(parsing: item) { ids.insert(id) }
        }
        return ids
    }

    /// The agents that a click starts without their prompts, with their flags: those the switch gives a flag, and those whose own command, arguments, first-prompt flag or start options type one.
    public static func withoutAsking(_ config: Config) -> [Entry] {
        let offered = offeredAgents(config)
        return config.allAgents.compactMap { agent in
            guard offered.contains(agent.id), let flag = config.launchOptions(for: agent).bypassFlag ?? config.bypassFlagTypedAnywhere(by: agent) else { return nil }
            return Entry(agent: agent.id, name: agent.name, flag: flag)
        }
    }

    /// What `after` starts without prompts that `before` did not: an agent that is new in that list, or one that is given another flag. An agent that asks again is not listed.
    public static func newlyWithoutAsking(from before: Config, to after: Config) -> [Entry] {
        let was = Dictionary(withoutAsking(before).map { ($0.agent, $0.flag) }, uniquingKeysWith: { first, _ in first })
        return withoutAsking(after).filter { was[$0.agent] != $0.flag }
    }
}
