import Foundation
import RightHereCore
import RightHereKit

// Changing an agent's start options (ADR 0026): the page of one of them, which the page of its agent opens, and the list of arguments that an agent and a start option share. A start option is
// an entry of a file, so a change names the entry by its place under the check that it is still the one that was shown, and goes to the file that holds it (`AgentVariants`, as
// `PresetOptions` does for the presets).

/// The list of arguments that is edited: an agent's own, or one start option's.
enum ArgumentListOwner: Hashable, Sendable {
    case agent(String)
    case variant(agent: String, id: String)

    /// Names the list among the lists of a page, so that a drag of one is not taken for a drop on another.
    var scope: String {
        switch self {
        case .agent(let id): id
        case .variant(let agent, let id): "\(agent).\(id)"
        }
    }
}

/// A start option of an agent, as the window names the page that shows it.
struct VariantRef: Hashable, Sendable {
    var agent: String
    var id: String
}

extension SetupModel {
    func variant(_ agent: String, _ id: String) -> VariantRowState? {
        agentOptions(agent)?.variants.first { $0.id == id }
    }

    /// Writes what `build` makes of the start option as it is now, to the file that holds it. Nothing to change is done; a start option that is not there is not.
    /// - Parameter byPlace: The change is worked out from what the page showed and is dropped when another change is being written (a button, a drag), as a change of the menu is.
    @discardableResult
    private func changeVariant(_ agent: String, _ id: String, byPlace: Bool = false, _ build: (VariantRowState) -> FileChange?) async -> Bool {
        if byPlace {
            guard !isWorking else { return false }
        } else {
            guard await settled(on: .agents, key: "agent.\(agent).variant.\(id)") else { return false }
        }
        guard let options = agentOptions(agent), let row = options.variants.first(where: { $0.id == id }) else { return false }
        guard let change = build(row) else { return true }
        return await edit(change.operations, deciding: "agent.\(agent).variant.\(id)", target: change.target, saying: .appAgentEdited(options.name), on: .agents)
    }

    @discardableResult
    func setVariantTitle(_ agent: String, _ id: String, _ title: String) async -> Bool {
        await changeVariant(agent, id) { AgentVariants.changing(title: title, of: $0, agent: agent) }
    }

    /// A start option for the agent, with a title and no arguments yet, written next to the agent's table. The id of the one that was made, which is not necessarily the last of the list (an entry of
    /// this Mac's own file comes after the shared ones); `nil` when it was not made.
    @discardableResult
    func createVariant(agent: String, title: String) async -> String? {
        // What the files already hold is asked before the wait: a change that starts in a gap after it would find the window busy and drop this one without a word.
        let used = await actions.entryIDsInUse(of: AgentVariants.table(of: agent))
        guard await settled(on: .agents, key: AgentVariants.table(of: agent)), let options = agentOptions(agent) else { return nil }
        guard let made = AgentVariants.creating(title: title, agent: options, alsoTaken: used) else { return nil }
        await edit(made.operations, deciding: AgentVariants.table(of: agent), anchor: anchor(of: options), saying: .appMenuEditedAdded(title.trimmingCharacters(in: .whitespaces)), on: .agents)
        return variant(agent, made.id) != nil ? made.id : nil
    }

    /// A start option taken out; its page closes with it.
    func removeVariant(_ agent: String, _ id: String) async {
        // The entry that the page showed is the one taken out: a second click, with an entry of that id in the other file as well, would find that one.
        let shown = variant(agent, id)?.entry
        await changeVariant(agent, id) { row in
            guard row.entry == shown else {
                say(.listChanged)
                return nil
            }
            return AgentVariants.removing(row, agent: agent)
        }
    }

    // MARK: Lists of arguments

    func argumentList(of owner: ArgumentListOwner) -> ArgumentList? {
        switch owner {
        case .agent(let id): agentOptions(id)?.argumentList
        case .variant(let agent, let id): variant(agent, id)?.arguments
        }
    }

    @discardableResult
    func addArgument(_ owner: ArgumentListOwner, _ argument: String) async -> Bool {
        switch owner {
        case .agent(let id): await addAgentArgument(id, argument)
        case .variant(let agent, let id): await changeVariant(agent, id) { AgentVariants.change($0.arguments.adding(argument), of: $0, agent: agent) }
        }
    }

    /// The argument at `position` (from 1) taken out.
    @discardableResult
    func removeArgument(_ owner: ArgumentListOwner, at position: Int) async -> Bool {
        switch owner {
        case .agent(let id): await removeAgentArgument(id, at: position)
        case .variant(let agent, let id): await changeVariant(agent, id, byPlace: true) { AgentVariants.change($0.arguments.removing(at: position), of: $0, agent: agent) }
        }
    }

    /// The argument at `position` (from 1), which the field showed as `shown`, written another way.
    @discardableResult
    func setArgument(_ owner: ArgumentListOwner, at position: Int, from shown: String, to argument: String) async -> Bool {
        switch owner {
        case .agent(let id): await setAgentArgument(id, at: position, from: shown, to: argument)
        case .variant(let agent, let id): await changeVariant(agent, id) { AgentVariants.change($0.arguments.setting(at: position, to: argument, expecting: shown), of: $0, agent: agent) }
        }
    }

    /// The arguments, one place up or down; the same drag as the other lists.
    @discardableResult
    func moveArguments(_ owner: ArgumentListOwner, from source: IndexSet, to destination: Int) async -> Bool {
        switch owner {
        case .agent(let id): await moveAgentArguments(id, from: source, to: destination)
        case .variant(let agent, let id): await changeVariant(agent, id, byPlace: true) { AgentVariants.change($0.arguments.moving(source, to: destination), of: $0, agent: agent) }
        }
    }

    /// The argument at `position` (from 1) one place up (`-1`) or down (`1`), for the context menu and for VoiceOver.
    @discardableResult
    func moveArgument(_ owner: ArgumentListOwner, _ position: Int, by offset: Int) async -> Bool {
        guard let count = argumentList(of: owner)?.items.count, (1...max(count, 1)).contains(position), (1...max(count, 1)).contains(position + offset) else { return false }
        return await moveArguments(owner, from: IndexSet(integer: position - 1), to: offset > 0 ? position + 1 : position - 2)
    }
}
