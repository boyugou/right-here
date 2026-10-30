import Foundation

/// What a person says they use: the flags of `rh setup` and `rh init`, or the pickers of the setup window. A choice that was
/// not made is `nil` and the machine decides (the first installed terminal, the first installed editor, the agents the login
/// shell finds). `agents == []` is a choice, and it means none.
public struct SetupChoices: Sendable, Equatable {
    public var terminal: String?
    public var editor: String?
    public var agents: [String]?

    public init(terminal: String? = nil, editor: String? = nil, agents: [String]? = nil) {
        self.terminal = terminal
        self.editor = editor
        self.agents = agents
    }

    /// Nothing was said, so nothing is checked against an existing config either.
    public var isEmpty: Bool { terminal == nil && editor == nil && agents == nil }

    /// The word that says "no agents" in `--agents none`. No agent has this id.
    public static let noAgents = "none"

    /// Checks what a person typed against the terminals, editors and agents Right Here knows, and says what is wrong in a
    /// sentence an AI agent can act on: the closest known id, and the ids there are. An id is exact: a name such as
    /// "Visual Studio Code" is not taken for `vscode`, it leads to it ("did you mean").
    public static func parse(terminal: String?, editor: String?, agents: String?) throws -> SetupChoices {
        var choices = SetupChoices()
        if let terminal { choices.terminal = try knownApp(terminal, role: .terminal) }
        if let editor { choices.editor = try knownApp(editor, role: .editor) }
        if let agents { choices.agents = try knownAgents(agents) }
        return choices
    }

    /// Why agents will not start in a terminal that cannot run a command, or `nil`. A config can still name it as the default
    /// terminal (it opens folders), so this is advice and not an error.
    public static func agentTerminalWarning(terminal: String?, agents: [String]) -> String? {
        guard !agents.isEmpty, let terminal, let app = KnownApps.terminal(id: terminal) else { return nil }
        guard let refusal = TerminalAdapters.adapter(for: app).commandRefusal else { return nil }
        let capable = KnownApps.terminals.filter { TerminalAdapters.adapter(for: $0).supportsCommands }.map(\.id).joined(separator: ", ")
        return "\(refusal) Agents start in a terminal that can run commands (\(capable)): choose one of those with --terminal."
    }

    private static func knownApp(_ word: String, role: AppDescriptor.Role) throws -> String {
        let id = word.trimmingCharacters(in: .whitespaces)
        let wanted = role == .terminal ? KnownApps.terminals : KnownApps.editors
        let other = role == .terminal ? KnownApps.editors : KnownApps.terminals
        let noun = role == .terminal ? "terminal" : "editor"
        let flag = role == .terminal ? "--terminal" : "--editor"
        let otherFlag = role == .terminal ? "--editor" : "--terminal"
        if wanted.contains(where: { $0.id == id }) { return id }
        let list = wanted.map(\.id).joined(separator: ", ")
        if other.contains(where: { $0.id == id }) {
            throw SetupChoiceError(message: "\"\(id)\" is \(role == .terminal ? "an editor" : "a terminal"), not \(role == .terminal ? "a terminal" : "an editor"). "
                + "Use \(otherFlag) \(id) for it, and give \(flag) one of: \(list).")
        }
        let hint = Suggestion.didYouMean(id, in: wanted.map { ($0.id, $0.name) }).map { " (\($0.text))" } ?? ""
        throw SetupChoiceError(message: "Unknown \(noun) \"\(id.withControlCharactersEscaped)\"\(hint). The \(noun)s Right Here knows: \(list). `rh apps` lists them with their names.")
    }

    private static func knownAgents(_ list: String) throws -> [String] {
        let words = list.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if words == [noAgents] { return [] }
        guard !words.contains(where: \.isEmpty) else {
            throw SetupChoiceError(message: "--agents takes agent ids separated by commas (for example claude,codex), or \(noAgents) for no agent at all.")
        }
        if words.contains(noAgents) {
            throw SetupChoiceError(message: "--agents \(noAgents) means no agent at all, so it cannot be combined with agent ids.")
        }
        var chosen: [String] = []
        for word in words {
            guard KnownAgents.agent(id: word) != nil else {
                let hint = Suggestion.didYouMean(word, in: KnownAgents.all.map { ($0.id, $0.name) }).map { " (\($0.text))" } ?? ""
                throw SetupChoiceError(message: "Unknown agent \"\(word.withControlCharactersEscaped)\"\(hint). The agents Right Here knows: "
                    + KnownAgents.all.map(\.id).joined(separator: ", ")
                    + ". An agent that is not built in is defined in the config, in an [agent.<id>] table (`rh docs config`).")
            }
            if !chosen.contains(word) { chosen.append(word) }
        }
        return chosen
    }
}

/// A choice that is not one Right Here knows. The message names the closest id and lists the ids, in English: it is for the
/// person who typed the flag or for the AI agent that did.
public struct SetupChoiceError: Error, Equatable, LocalizedError {
    public var message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

extension DetectedEnvironment {
    /// What the machine found, with what the person said put over it.
    public func applying(_ choices: SetupChoices) -> DetectedEnvironment {
        DetectedEnvironment(terminal: choices.terminal ?? terminal, editor: choices.editor ?? editor, agents: choices.agents ?? agents)
    }
}
