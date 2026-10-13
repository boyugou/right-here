import Foundation

/// What a config can make Right Here start: the argument vectors of its terminal templates, the command, first-prompt
/// flag and variant arguments of each agent, the default terminal when that terminal starts through a template, and a
/// terminal app that the config lists as another kind of app.
///
/// A config that arrives from the sync folder is compared with the one it would replace through this, because a
/// folder that other machines, a sync service or a shared drive can write must not be able to make a click run a
/// program the person never saw (docs/decisions/0013-config-sync.md, "Trust"). It also lists a terminal that the
/// config gives another role, which makes files be handed to it. Everything else a config sets is a choice among
/// things Right Here already does or among apps already installed here (the ADR says what that leaves unguarded).
public struct LaunchCommands: Sendable, Equatable {
    /// One setting that decides what is started.
    public struct Entry: Sendable, Equatable {
        /// Where the config sets it, in config terms: `[[app]] terminal run_args`, `[agent.claude] command`.
        public var place: String
        /// What it is set to, printable: strings are quoted and control characters are escaped.
        public var value: String
    }

    /// An entry that is new, or that says something other than before.
    public struct Change: Sendable, Equatable {
        public var place: String
        public var value: String
        /// What the same place said before; `nil` when the place is new.
        public var previous: String?

        /// One line for a terminal: `[agent.claude] command = "claude --x" (was "claude")`.
        public var line: String {
            "\(place) = \(value)" + (previous.map { " (was \($0))" } ?? "")
        }
    }

    /// Sorted by place; every place once.
    public let entries: [Entry]

    public init(_ config: Config) {
        var found: [Entry] = []
        for app in config.apps {
            // Only an app with a template starts a program of its own; the others are driven by code Right Here has or are
            // handed the folder.
            guard case .template(let launch) = app.driver else { continue }
            if let open = launch.open { found.append(Entry(place: "[[app]] \(app.id) open_args", value: Self.list(open))) }
            if let run = launch.run { found.append(Entry(place: "[[app]] \(app.id) run_args", value: Self.list(run))) }
            // `{app}` in a template resolves through the bundle identifiers, so they decide which program runs.
            found.append(Entry(place: "[[app]] \(app.id) bundle_ids", value: Self.list(app.bundleIDs)))
        }
        // A terminal is only ever handed a folder, because handed a file it runs it, and what says an app is a terminal is
        // its role. An `[[app]]` that carries a terminal's bundle identifier with another role makes Right Here hand it files.
        let terminalBundles = Set(KnownApps.terminals.flatMap(\.bundleIDs) + config.apps.filter { $0.role == .terminal }.flatMap(\.bundleIDs))
        for app in config.apps where app.role != .terminal && !terminalBundles.isDisjoint(with: app.bundleIDs) {
            found.append(Entry(place: "[[app]] \(app.id) role (a terminal handed a file runs it)", value: Self.quoted(app.role.rawValue)))
        }
        // The agents as they will run: a built-in one the config does not touch says the same on both sides of a
        // comparison and never shows up.
        for agent in config.allAgents {
            found.append(Entry(place: "[agent.\(agent.id)] command", value: Self.quoted(agent.command)))
            if let argument = agent.promptArgument { found.append(Entry(place: "[agent.\(agent.id)] prompt_arg", value: Self.quoted(argument.configValue))) }
            for variant in agent.variants {
                found.append(Entry(place: "[[agent.\(agent.id).variant]] \(variant.id) arguments", value: Self.list(variant.arguments)))
            }
        }
        // The choice alone starts nothing, so a built-in terminal is not listed; one that starts through a template is.
        if let id = config.terminal, case .template? = config.app(id: id)?.driver {
            found.append(Entry(place: "[general] terminal (starts through a command template)", value: Self.quoted(id)))
        }
        var seen = Set<String>()
        entries = found.filter { seen.insert($0.place).inserted }.sorted { $0.place < $1.place }
    }

    /// The config in `text`, as it applies when read alone (the same reading that validated it).
    public init(configText text: String) {
        self.init(ConfigParser.parse(text).config)
    }

    /// The config in a file's bytes. What cannot be read as text applies as nothing at all, so everything custom in a
    /// config compared against it counts as new.
    public init(configData data: Data) {
        guard var text = String(data: data, encoding: .utf8) else { self.init(Config.default); return }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        self.init(configText: text)
    }

    /// What this has that `known` does not: places `known` lacks, and places where the value differs. Something
    /// `known` has and this lacks is a removal, which starts nothing, and is not listed.
    public func additions(to known: LaunchCommands) -> [Change] {
        let before = Dictionary(known.entries.map { ($0.place, $0.value) }, uniquingKeysWith: { first, _ in first })
        return entries.compactMap { entry in
            before[entry.place] == entry.value ? nil : Change(place: entry.place, value: entry.value, previous: before[entry.place])
        }
    }

    /// The settings that differ from the built-in ones: what this config starts that Right Here does not start by itself.
    public var custom: [Change] {
        additions(to: LaunchCommands(.default))
    }

    static func quoted(_ text: String) -> String {
        "\"" + text.scalarReplacing(["\\": "\\\\", "\"": "\\\""]).withControlCharactersEscaped + "\""
    }

    static func list(_ elements: [String]) -> String {
        "[" + elements.map(quoted).joined(separator: ", ") + "]"
    }
}
