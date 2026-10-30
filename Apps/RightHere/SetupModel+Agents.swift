import Foundation
import RightHereCore
import RightHereKit

// Changing one agent's own options (ADR 0026): the page of an agent that the Agents page opens.
//
// A setting that holds one value (the command, the terminal, a flag) is worked out from the options as they are when the change is made, after the change that is running has ended: a
// field that loses its focus as the next control is used makes its change while that control's change is made, and both must reach the config. A change by place in the list of
// arguments (a button, a drag) is worked out from the options the page showed when it was asked for, and is dropped when another change is being written, as a change of the menu is:
// a second click on the same minus must not take out the argument that moved up under it.

/// Whether a new terminal window would find an agent's command: what its login shell said when the checks last ran.
enum AgentCommandState: Equatable {
    /// Found; with where, when `command -v` gave a path (an alias or a function has none).
    case found(path: String?)
    case missing
    /// The shell did not get to the end of the question (a startup file that exits or waits), so nobody knows.
    case unknown
}

extension SetupModel {
    /// What the login shell said of an agent's command; `nil` when it was not asked (before the first checks, or for an agent added since).
    func commandState(of agent: GeneralSettingsState.Agent) -> AgentCommandState? {
        guard let shell = snapshot?.agentCommands, shell.asked.contains(agent.executable) else { return nil }
        if shell.found.contains(agent.executable) {
            return .found(path: shell.locations[agent.executable].flatMap { $0.hasPrefix("/") ? PathDisplay.abbreviatingHome($0, home: homePath) : nil })
        }
        return shell.answered ? .missing : .unknown
    }

    /// The agents the menu does not offer, as the Agents page lists them: the ones the login shell has first, then the ones nobody knows about (the
    /// shell was not asked, or did not get to the end); and apart, the ones it said it does not have.
    func agentsOutOfMenu(_ general: GeneralSettingsState) -> (others: [GeneralSettingsState.Agent], missing: [GeneralSettingsState.Agent]) {
        let out = general.agents.filter { !$0.enabled }
        let found = out.filter { if case .found = commandState(of: $0) { true } else { false } }
        let missing = out.filter { commandState(of: $0) == .missing }
        let unknown = out.filter { agent in !found.contains { $0.id == agent.id } && !missing.contains { $0.id == agent.id } }
        return (found + unknown, missing)
    }

    /// Whether the agents the login shell does not have are listed when the page opens: only when it has none of them, for then they are
    /// what the page has to offer. With one found they are a folded line with their number, which a click opens; fifteen lines of
    /// agents someone has not installed put the presets out of sight.
    func listsMissingAgentsAtFirst(_ general: GeneralSettingsState) -> Bool {
        !general.agents.contains { if case .found = commandState(of: $0) { true } else { false } }
    }

    /// One agent's options to edit; `nil` while the config cannot be edited (it has an error, or there is none), or when no agent has this id.
    func agentOptions(_ id: String) -> AgentOptionsState? {
        snapshot?.agentOptions.first { $0.id == id }
    }

    /// Waits for the change that is running to end, and says whether the window is free then.
    func settled() async -> Bool {
        let deadline = ContinuousClock.now + patience
        // A change that is called off (a block of text that kept being typed in cancels its rest) stops waiting: a cancelled sleep ends at once, and the loop would spin for what is left of the time.
        while isWorking, !Task.isCancelled, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return !isWorking
    }

    /// Waits for the change that is running to end. When the window is busy for longer than a change waits, the change is not made, and it is said under the editor it was made in (a field
    /// that kept what was typed would otherwise write it later, and one that was left would lose it without a word).
    func settled(on tab: SetupTab, key: String) async -> Bool {
        guard await settled() else {
            // A change that was called off is not a change that the window was too busy for: nothing is said.
            if !Task.isCancelled { refuseBusy(on: tab, key: key) }
            return false
        }
        return true
    }

    /// What the keys of an agent of one's own stand on: the file that makes its table is the one they go to when this Mac's own file does not write them itself.
    func anchor(of options: AgentOptionsState) -> String? {
        options.isBuiltIn ? nil : "agent.\(options.id).command"
    }

    /// Writes what `operations` make of the options as they are now, to the file that decides the setting.
    @discardableResult
    private func change(_ id: String, deciding setting: String, _ operations: (AgentOptionsState) -> [ConfigOperation]) async -> Bool {
        guard await settled(on: .agents, key: "agent.\(id).\(setting)"), let options = agentOptions(id) else { return false }
        return await edit(operations(options), deciding: "agent.\(id).\(setting)", anchor: anchor(of: options), saying: .appAgentEdited(options.name), on: .agents)
    }

    /// Writes what `operations` make of the options the page showed, unless another change is being written.
    @discardableResult
    private func changeByPlace(_ id: String, deciding setting: String, _ operations: (AgentOptionsState) -> [ConfigOperation]) async -> Bool {
        guard !isWorking, let options = agentOptions(id) else { return false }
        return await edit(operations(options), deciding: "agent.\(id).\(setting)", anchor: anchor(of: options), saying: .appAgentEdited(options.name), on: .agents)
    }

    /// The name an agent of one's own has in the menu.
    @discardableResult
    func setAgentName(_ id: String, _ name: String) async -> Bool {
        await change(id, deciding: "name") { AgentOptions.operations(settingName: name, of: $0) }
    }

    /// What is typed to start the agent.
    @discardableResult
    func setAgentCommand(_ id: String, _ command: String) async -> Bool {
        await change(id, deciding: "command") { AgentOptions.operations(settingCommand: command, of: $0) }
    }

    @discardableResult
    func setAgentLauncher(_ id: String, _ launcher: AgentOptionsState.Launcher) async -> Bool {
        await change(id, deciding: "launcher") { AgentOptions.operations(settingLauncher: launcher, of: $0) }
    }

    /// The terminal the agent is typed into; `nil` is the default terminal.
    @discardableResult
    func setAgentTerminal(_ id: String, _ terminal: String?) async -> Bool {
        await change(id, deciding: "terminal") { AgentOptions.operations(settingTerminal: terminal, of: $0) }
    }

    /// Whether the agent starts with its permission prompts switched off, whatever the switch for all agents says; `nil` follows the switch. A change after which the agent starts without
    /// asking and did not before is held for the person's yes (`edit`), whichever of the controls it comes from.
    @discardableResult
    func setAgentBypass(_ id: String, _ override: Bool?) async -> Bool {
        await change(id, deciding: "bypass_permissions") { AgentOptions.operations(settingBypass: override, of: $0) }
    }

    /// The flag that switches the agent's permission prompts off, when it is not the one built in; empty takes it out. Held for the person's yes when the agent would start without asking.
    @discardableResult
    func setAgentBypassArgument(_ id: String, _ argument: String) async -> Bool {
        await change(id, deciding: "bypass_permission_arg") { AgentOptions.operations(settingBypassArgument: argument, of: $0) }
    }

    /// How the agent takes a first prompt: `positional`, or the flag that carries it; empty, or the built-in way, takes the setting out.
    @discardableResult
    func setAgentPromptArgument(_ id: String, _ word: String) async -> Bool {
        await change(id, deciding: "prompt_arg") { AgentOptions.operations(settingPromptArgument: word, of: $0) }
    }

    @discardableResult
    func addAgentArgument(_ id: String, _ argument: String) async -> Bool {
        await change(id, deciding: "args") { AgentOptions.operations(addingArgument: argument, to: $0) }
    }

    /// The argument at `position` (from 1) taken out.
    @discardableResult
    func removeAgentArgument(_ id: String, at position: Int) async -> Bool {
        await changeByPlace(id, deciding: "args") { AgentOptions.operations(removingArgumentAt: position, of: $0) }
    }

    /// The argument at `position` (from 1), which the field showed as `shown`, written another way.
    @discardableResult
    func setAgentArgument(_ id: String, at position: Int, from shown: String, to argument: String) async -> Bool {
        await change(id, deciding: "args") { AgentOptions.operations(settingArgumentAt: position, to: argument, of: $0, expecting: shown) }
    }

    /// The arguments, one place up or down; the same drag as the lists of the menu and of the agents.
    @discardableResult
    func moveAgentArguments(_ id: String, from source: IndexSet, to destination: Int) async -> Bool {
        await changeByPlace(id, deciding: "args") { AgentOptions.operations(movingArguments: source, to: destination, of: $0) }
    }

    /// An agent of one's own taken out of the menu and out of the config; its page closes with it. The menu's entry and the table are usually in one file, and one change takes both
    /// (one Undo). When they are in two, the entry goes first: a table that nothing lists is a config that reads, and a list that names a table that is gone is not.
    func removeAgent(_ id: String) async {
        guard await settled(on: .agents, key: "agent.\(id).command"), let general, let options = agentOptions(id), let removal = AgentOptions.operations(removing: options, in: general) else { return }
        let key = "agent.\(id).command"
        let message = LocalizedMessage.appMenuEditedRemoved(options.name)
        if !removal.isListed {
            await edit(removal.table, deciding: key, saying: message, on: .agents)
        } else if await actions.owner(of: GeneralSettingsState.agentsKey) == actions.owner(of: key) {
            await edit(removal.all, deciding: key, saying: message, on: .agents)
        } else if await edit(removal.list, deciding: GeneralSettingsState.agentsKey, saying: message, on: .agents) {
            await edit(removal.table, deciding: key, saying: message, on: .agents)
        }
    }

    /// A program of one's own as an agent, put in the menu after the others. Whether it was made: the name and the command may be refused (nothing typed, a list of agents that is not the one
    /// that is shown).
    @discardableResult
    func createAgent(name: String, command: String) async -> Bool {
        let used = await actions.disableableIDsInUse()
        guard await settled(on: .agents, key: GeneralSettingsState.agentsKey), let general else { return false }
        guard let made = AgentOptions.operations(creating: name, command: command, in: general, alsoTaken: used) else { return false }
        await edit(made.operations, deciding: GeneralSettingsState.agentsKey, saying: .appMenuEditedAdded(name.trimmingCharacters(in: .whitespaces)), on: .agents)
        return agentOptions(made.id) != nil
    }
}
