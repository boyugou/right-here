import CryptoKit
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
        /// What two configs are compared by: the value, or the whole text that a long value shows only the start of. A copy
        /// that kept the start, the length and a short digest of a text would otherwise pass for the same.
        public var identity: String

        public init(place: String, value: String, identity: String? = nil) {
            self.place = place
            self.value = value
            self.identity = identity ?? value
        }
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
        // The system finds an app by its bundle identifier whatever the case, so the identifiers are compared without regard to it.
        let terminalBundles = Set((KnownApps.terminals.flatMap(\.bundleIDs) + config.apps.filter { $0.role == .terminal }.flatMap(\.bundleIDs)).map { $0.lowercased() })
        for app in config.apps where app.role != .terminal && !terminalBundles.isDisjoint(with: app.bundleIDs.map { $0.lowercased() }) {
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
            // What a start adds to the command is listed as what it is: a flag that switches the agent's own permission prompts off, and the
            // person's own arguments. A config that turns the first on says so here, in those words, and not as a changed command.
            let options = config.launchOptions(for: agent)
            if let flag = options.bypassFlag {
                found.append(Entry(place: "[agent.\(agent.id)] bypass_permissions (starts the agent with its permission prompts switched off)", value: Self.quoted(flag)))
            }
            // The flag the config gives the agent is typed when the switch is turned on, so it is listed whether or not the switch is on now: the person who turns it on later is not asked again.
            if let own = config.agents[agent.id]?.bypassPermissionArgument {
                found.append(Entry(place: "[agent.\(agent.id)] bypass_permission_arg (typed when the permission prompts are switched off)", value: Self.quoted(own)))
            }
            if !options.arguments.isEmpty { found.append(Entry(place: "[agent.\(agent.id)] args", value: Self.list(options.arguments))) }
        }
        // An agent that a click can start without its permission prompts, and the flag that does it: a copy that only puts an agent in the menu (or in the Quick Actions) while the switch is on, or
        // that puts one there whose own command types the flag, changes no line above, and is the same change as one an assistant would have to wait for (`PromptEffects`).
        for entry in PromptEffects.withoutAsking(config) {
            found.append(Entry(place: "[agent.\(entry.agent)] offered with its permission prompts switched off (it is in the menu or the Quick Actions)", value: Self.quoted(entry.flag)))
        }
        // What a new file holds becomes a file that something may run (a script, a login item) in any folder the tool that makes it is given, so it is listed as well. A long text is shown by its
        // start and a digest, and compared whole.
        for template in config.newFile.templates where !template.contents.isEmpty {
            found.append(Entry(place: "[[new_file.template]] \(template.id) contents (becomes a file that something on this Mac may run)", value: Self.digested(template.contents),
                               identity: template.contents))
        }
        // The choice alone starts nothing, so a built-in terminal is not listed; one that starts through a template is, whoever makes the choice: the default terminal, an agent's own terminal, an item of
        // the menu or of the Quick Actions that names one.
        for use in config.templateTerminalUses {
            found.append(Entry(place: "\(use.place) (starts through a command template)", value: Self.quoted(use.terminal)))
        }
        var seen = Set<String>()
        entries = found.filter { seen.insert($0.place).inserted }.sorted { $0.place < $1.place }
    }

    /// For tests: entries as they are given.
    init(entries: [Entry]) {
        self.entries = entries
    }

    /// The config in `text`, as it applies when read alone (the same reading that validated it).
    public init(configText text: String) {
        self.init(ConfigParser.parse(text).config)
    }

    /// The config in a file's bytes. What cannot be read as text, or is past the size a config may have (it is never
    /// parsed: that is what the limit is for), applies as nothing at all, so everything custom in a config compared
    /// against it counts as new.
    public init(configData data: Data) {
        guard let text = Self.text(of: data) else { self.init(Config.default); return }
        self.init(configText: text)
    }

    /// The config in a file's bytes as it applies on a Mac whose own file, `config.local.toml`, is `overlay`: that file decides settings that belong to the Mac (the switch that starts agents without
    /// asking, a terminal that only it defines), and the shared file that a pull replaces is read with it. An overlay that cannot be read is left out, as it is when the config is read.
    public init(configData data: Data, overlay: Data?) {
        guard let text = Self.text(of: data) else { self.init(Config.default); return }
        let local = overlay.flatMap(Self.text(of:)).map(ConfigSource.text) ?? .absent
        self.init(ConfigLayers.load(base: .text(text), local: local).config)
    }

    private static func text(of data: Data) -> String? {
        guard data.count <= ConfigParser.maxBytes, var text = String(data: data, encoding: .utf8) else { return nil }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    /// What this has that `known` does not: places `known` lacks, and places where the value differs. Something
    /// `known` has and this lacks is a removal, which starts nothing, and is not listed; with one exception: the arguments
    /// of an agent that is still there. They may be what keeps it in its sandbox (`--sandbox read-only`), so an agent that
    /// is started with none is started with something other than before.
    public func additions(to known: LaunchCommands) -> [Change] {
        let before = Dictionary(known.entries.map { ($0.place, $0) }, uniquingKeysWith: { first, _ in first })
        var changes = entries.compactMap { entry in
            before[entry.place]?.identity == entry.identity ? nil : Change(place: entry.place, value: entry.value, previous: before[entry.place]?.value)
        }
        let places = Set(entries.map(\.place))
        for entry in known.entries where entry.place.hasSuffix("] args") && !places.contains(entry.place) && places.contains(entry.place.dropLast(" args".count) + " command") {
            changes.append(Change(place: entry.place, value: "[]", previous: entry.value))
        }
        return changes
    }

    /// The settings that differ from the built-in ones: what this config starts that Right Here does not start by itself.
    public var custom: [Change] {
        additions(to: LaunchCommands(.default))
    }

    static func quoted(_ text: String) -> String {
        "\"" + text.scalarReplacing(["\\": "\\\\", "\"": "\\\""]).withControlCharactersEscaped + "\""
    }

    /// A long text as its start, its size and a digest of all of it, so that two texts that start alike are not the same entry and a line of a refusal stays a line.
    static func digested(_ text: String) -> String {
        let bytes = Data(text.utf8)
        if bytes.count <= 160 { return quoted(text) }
        let digest = SHA256.hash(data: bytes).prefix(6).map { String(format: "%02x", $0) }.joined()
        return quoted(String(text.prefix(120))) + "… (\(bytes.count) bytes, sha256 \(digest)…)"
    }

    static func list(_ elements: [String]) -> String {
        "[" + elements.map(quoted).joined(separator: ", ") + "]"
    }
}
