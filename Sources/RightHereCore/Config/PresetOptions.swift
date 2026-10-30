import Foundation

/// One prompt preset as a line to edit in the window (ADR 0026).
public struct PresetRowState: Sendable, Equatable, Identifiable {
    public enum Origin: Sendable, Equatable {
        /// One the app has built in and the config does not touch: it can be read, and made the person's own.
        case builtIn
        /// A built-in id that the config writes an entry for: the config's wording replaces the built-in one, and taking the entry out puts the built-in one back.
        case customized
        /// One the config defines.
        case own
    }

    /// Where the config writes it: the entries of `[[preset]]`.
    public typealias Entry = EntryLocation

    public var id: String
    /// As it is shown: the built-in titles are in the person's language.
    public var title: String
    public var prompt: String
    /// The agent that runs it; `nil` is the first agent in the menu.
    public var agent: String?
    public var maxFiles: Int
    public var origin: Origin
    /// `nil` for a built-in preset that the config does not touch, and for one that the config writes in a form with no place to edit it by (an inline array).
    public var entry: Entry?
    /// The shared file writes an entry for this built-in preset that this Mac leaves out (its agent is turned off here): customizing it writes this Mac's own file, which replaces that entry by id,
    /// since a second entry with the id in the shared file would be a duplicate.
    public var hiddenInShared = false

    public init(id: String, title: String, prompt: String, agent: String?, maxFiles: Int, origin: Origin, entry: Entry?) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.agent = agent
        self.maxFiles = maxFiles
        self.origin = origin
        self.entry = entry
    }
}

/// The prompt presets of the config as lines to edit, and the agents a preset can name.
public struct PresetsState: Sendable, Equatable {
    /// An agent that takes a first prompt, which is what a preset needs.
    public struct Agent: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public var rows: [PresetRowState]
    public var agents: [Agent]

    public init(rows: [PresetRowState], agents: [Agent]) {
        self.rows = rows
        self.agents = agents
    }

    public func row(id: String) -> PresetRowState? { rows.first { $0.id == id } }
}

public enum PresetOptions {
    /// The changes of one edit and the file they go to: a preset is an entry of a file, and which file is the one that holds it, not the one that decides a key of that position.
    public typealias Change = FileChange

    /// The presets of `config` as lines to edit.
    /// - Parameters:
    ///   - entries: Where each preset the config writes is (`ConfigService.presetEntries`).
    ///   - written: The ids of the presets the config writes an entry for, in whatever form (`ConfigLoadResult.entryOrigins`); an entry that has no place to edit it by is still written. By default
    ///     the ids that have a place.
    ///   - hiddenInShared: Ids that the shared file writes and this Mac leaves out.
    public static func state(config: Config, entries: [String: PresetRowState.Entry], written: Set<String>? = nil, hiddenInShared: Set<String> = [], localizer: Localizer) -> PresetsState {
        let builtIn = Set(AgentPreset.builtIn.map(\.id))
        let written = written ?? Set(entries.keys)
        let rows = config.presets.map { preset -> PresetRowState in
            let entry = entries[preset.id]
            // A preset that the config writes in a form that cannot be edited by place (an inline array) is the config's: not the built-in one, whatever its id, and not a copy of it to make.
            let origin: PresetRowState.Origin = builtIn.contains(preset.id) ? (written.contains(preset.id) ? .customized : .builtIn) : .own
            var row = PresetRowState(id: preset.id, title: preset.localizedTitle(localizer), prompt: preset.prompt, agent: preset.agent, maxFiles: preset.maxFiles, origin: origin, entry: entry)
            row.hiddenInShared = origin == .builtIn && hiddenInShared.contains(preset.id)
            return row
        }
        // An agent this Mac turns off is not offered: a preset that names it is left out here.
        return PresetsState(rows: rows, agents: config.allAgents.filter { $0.promptArgument != nil && !config.disabledAgents.contains($0.id) }.map { PresetsState.Agent(id: $0.id, name: $0.name) })
    }

    private static func key(_ position: Int, _ field: String) -> String { "preset.\(position).\(field)" }

    /// A change of the entry that holds `row`, on condition that the entry at that place is still `row`'s: a list that something else changed meanwhile is not changed in its place.
    private static func change(_ row: PresetRowState, at entry: EntryLocation, _ operations: [ConfigOperation]) -> Change {
        Change(target: entry.target, operations: [.expectEntry(row.id, at: entry.position, in: "preset")] + operations)
    }

    public static func changing(title: String, of row: PresetRowState) -> Change? {
        let text = title.trimmingCharacters(in: .whitespaces)
        guard let entry = row.entry, !text.isEmpty, text != row.title else { return nil }
        return change(row, at: entry, [.set(key(entry.position, "title"), .string(text))])
    }

    public static func changing(prompt: String, of row: PresetRowState) -> Change? {
        let text = prompt.trimmingCharacters(in: .whitespaces)
        guard let entry = row.entry, !text.isEmpty, text != row.prompt else { return nil }
        return change(row, at: entry, [.set(key(entry.position, "prompt"), .string(text))])
    }

    /// The agent that runs it; `nil` is the first agent of the menu, which is the setting taken out.
    public static func changing(agent: String?, of row: PresetRowState) -> Change? {
        guard let entry = row.entry, agent != row.agent else { return nil }
        return change(row, at: entry, [agent.map { .set(key(entry.position, "agent"), .string($0)) } ?? .unset(key(entry.position, "agent"))])
    }

    /// How many files it takes at most; the default is the setting taken out.
    public static func changing(maxFiles: Int, of row: PresetRowState) -> Change? {
        guard let entry = row.entry, (1...AgentPreset.maxFilesLimit).contains(maxFiles), maxFiles != row.maxFiles else { return nil }
        return change(row, at: entry, [maxFiles == AgentPreset.defaultMaxFiles ? .unset(key(entry.position, "max_files")) : .set(key(entry.position, "max_files"), .integer(maxFiles))])
    }

    /// A built-in preset made the person's own: an entry with its id, its title and its prompt, which then says what it says in place of the built-in one.
    public static func customizing(_ row: PresetRowState) -> Change? {
        guard row.origin == .builtIn else { return nil }
        return Change(target: row.hiddenInShared ? .local : .shared, operations: [.addEntry(to: "preset", fields: [ConfigField("id", .string(row.id)), ConfigField("title", .string(row.title)), ConfigField("prompt", .string(row.prompt))], at: nil)])
    }

    /// The entry taken out: a preset of one's own is gone, and a built-in one that was customized is the built-in one again.
    public static func removing(_ row: PresetRowState) -> Change? {
        guard let entry = row.entry else { return nil }
        return change(row, at: entry, [.removeEntry(at: entry.position, from: "preset")])
    }

    /// A new preset with its title and its prompt. The id is made from the title and is not one that a preset shown or a file has.
    /// - Parameter alsoTaken: Ids that the files mention and the config does not show (a preset the config left out for an error).
    public static func creating(title: String, prompt: String, in state: PresetsState, alsoTaken: Set<String> = []) -> (id: String, change: Change)? {
        let name = title.trimmingCharacters(in: .whitespaces), text = prompt.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !text.isEmpty else { return nil }
        let taken = Set(state.rows.map(\.id)).union(alsoTaken)
        let id = IDSlug.unique(IDSlug.make(from: name) ?? "preset") { taken.contains($0) }
        return (id, Change(target: .shared, operations: [.addEntry(to: "preset", fields: [ConfigField("id", .string(id)), ConfigField("title", .string(name)), ConfigField("prompt", .string(text))], at: nil)]))
    }
}
