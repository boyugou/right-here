import Foundation

/// One start option of an agent (a `[[agent.<id>.variant]]` entry) as a page to edit in the window (ADR 0026): a title for the menu and the arguments that are typed after the agent's command.
public struct VariantRowState: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    /// Its arguments as a list to edit; the key holds the place of its entry.
    public var arguments: ArgumentList
    /// Where the config writes it.
    public var entry: EntryLocation

    public init(id: String, title: String, arguments: ArgumentList, entry: EntryLocation) {
        self.id = id
        self.title = title
        self.arguments = arguments
        self.entry = entry
    }
}

/// A start option that the window only shows: one the agent has built in, and one that the config has but whose place it could not find.
public struct FixedVariant: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var arguments: [String]
    public var isBuiltIn: Bool
    /// The catalog text of a built-in title ("Continue Last Session"), which the menu shows in its language.
    public var titleKey: LocalizationKey?

    public init(id: String, title: String, arguments: [String], isBuiltIn: Bool, titleKey: LocalizationKey? = nil) {
        self.id = id
        self.title = title
        self.arguments = arguments
        self.isBuiltIn = isBuiltIn
        self.titleKey = titleKey
    }
}

public enum AgentVariants {
    /// The array of tables that holds the start options of an agent.
    public static func table(of agent: String) -> String { "agent.\(agent).variant" }

    private static func key(_ agent: String, _ position: Int, _ field: String) -> String { "\(table(of: agent)).\(position).\(field)" }

    /// The start options of `agent`: those the config writes as entries to edit, and the others to show.
    /// - Parameters:
    ///   - entries: Where each start option the config writes is (`ConfigService.entryLocations(of: "agent.<id>.variant")`).
    ///   - listed: What the file that holds each entry writes for its `arguments`, by the id of the entry.
    static func variants(of agent: String, config: Config, entries: [String: EntryLocation], listed: [String: [String]]) -> (own: [VariantRowState], fixed: [FixedVariant]) {
        let builtIn = Set((KnownAgents.agent(id: agent)?.variants ?? []).map(\.id))
        var own: [VariantRowState] = []
        var fixed: [FixedVariant] = []
        for variant in config.agent(id: agent)?.variants ?? [] {
            if !builtIn.contains(variant.id), let entry = entries[variant.id] {
                own.append(VariantRowState(id: variant.id, title: variant.title, arguments: ArgumentList(key: key(agent, entry.position, "arguments"), items: variant.arguments, listed: listed[variant.id]), entry: entry))
            } else {
                fixed.append(FixedVariant(id: variant.id, title: variant.title, arguments: variant.arguments, isBuiltIn: builtIn.contains(variant.id),
                                          titleKey: variant.titleKey))
            }
        }
        return (own, fixed)
    }

    /// A change of the entry that holds `row`, on condition that the entry at that place is still `row`'s.
    public static func change(_ operations: [ConfigOperation], of row: VariantRowState, agent: String) -> FileChange? {
        guard !operations.isEmpty else { return nil }
        return FileChange(target: row.entry.target, operations: [.expectEntry(row.id, at: row.entry.position, in: table(of: agent))] + operations)
    }

    public static func changing(title: String, of row: VariantRowState, agent: String) -> FileChange? {
        let text = title.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text != row.title else { return nil }
        return change([.set(key(agent, row.entry.position, "title"), .string(text))], of: row, agent: agent)
    }

    /// The entry taken out.
    public static func removing(_ row: VariantRowState, agent: String) -> FileChange? {
        change([.removeEntry(at: row.entry.position, from: table(of: agent))], of: row, agent: agent)
    }

    /// A new start option with a title, and no arguments yet. The id is made from the title and is not one that the agent has built in, that a start option shown has, or that a file has.
    /// - Parameters:
    ///   - rows: The agent's start options as they are.
    ///   - alsoTaken: Ids that the files write and the config does not show (`ConfigService.entryIDsInUse`).
    public static func creating(title: String, agent: AgentOptionsState, alsoTaken: Set<String> = []) -> (id: String, operations: [ConfigOperation])? {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let taken = Set(agent.variants.map(\.id) + agent.fixedVariants.map(\.id)).union(alsoTaken)
        let id = IDSlug.unique(IDSlug.make(from: name) ?? "variant") { taken.contains($0) }
        return (id, [.addEntry(to: table(of: agent.id), fields: [ConfigField("id", .string(id)), ConfigField("title", .string(name))], at: nil)])
    }
}
