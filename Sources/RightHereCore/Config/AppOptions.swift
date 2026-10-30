import Foundation

/// One app that the config adds, as a line to edit in the window (ADR 0026).
public struct AppRowState: Sendable, Equatable, Identifiable {
    public enum Origin: Sendable, Equatable {
        /// An app the config defines.
        case own
        /// The config's entry has the id of a built-in app and replaces it; taking the entry out brings the built-in one back.
        case replacesBuiltIn
    }

    public var id: String
    public var name: String
    public var role: AppDescriptor.Role
    /// The bundle identifiers the app is looked for by, most preferred first.
    public var bundleIDs: [String]
    public var icon: Icon?
    public var installed: Bool
    /// The config starts it through templates of its own (`open_args`, `run_args`): only the text of the config changes those, and a role other than a terminal would leave them without a meaning.
    public var usesTemplates: Bool
    /// It has the bundle identifier of a terminal that comes with Right Here. A terminal is only handed folders, because handed a file it runs it, so its role stays "terminal".
    public var isKnownTerminal: Bool
    public var origin: Origin
    /// Where the config writes it: the entries of `[[app]]`. `nil` for an entry written in a form with no place to edit it by (an inline array).
    public var entry: EntryLocation?

    /// The role is not the window's to change: the app is started through templates, or it is a terminal that is only handed folders.
    public var rolePinned: Bool { usesTemplates || isKnownTerminal }

    public init(id: String, name: String, role: AppDescriptor.Role, bundleIDs: [String], icon: Icon?, installed: Bool, usesTemplates: Bool, isKnownTerminal: Bool = false, origin: Origin, entry: EntryLocation?) {
        self.id = id
        self.name = name
        self.role = role
        self.bundleIDs = bundleIDs
        self.icon = icon
        self.installed = installed
        self.usesTemplates = usesTemplates
        self.isKnownTerminal = isKnownTerminal
        self.origin = origin
        self.entry = entry
    }
}

/// The apps the config adds as lines to edit, and what a new one must not take.
public struct AppsState: Sendable, Equatable {
    public var rows: [AppRowState]
    /// The apps that are there without the config's help or with it, by bundle identifier in lower case (the system finds an app by it whatever the case): what an app that is picked is called
    /// when it is available already.
    public var available: [String: String]
    /// The built-in apps that this Mac turns off (`disabled` in its own file), by bundle identifier in lower case: they are known, and not to be added again under another id.
    public var turnedOff: [String: String]
    /// Ids that a new app must not take: the ones in use (a built-in app's id would replace it), the ones a machine turns off, the words that name a launcher, and those of the agents and of the
    /// new-file templates: `disabled` is one list of ids for the three, so an id of one kind that another kind has would turn both off.
    public var takenIDs: Set<String>

    public init(rows: [AppRowState], available: [String: String], turnedOff: [String: String] = [:], takenIDs: Set<String>) {
        self.rows = rows
        self.available = available
        self.turnedOff = turnedOff
        self.takenIDs = takenIDs
    }

    public func row(id: String) -> AppRowState? { rows.first { $0.id == id } }
}

public enum AppOptions {
    /// The changes of one edit and the file they go to: an app is an entry of a file, and which file is the one that holds it, not the one that decides a key of that position.
    public typealias Change = FileChange

    /// The roles a person chooses from: what the app opens (a folder, in a terminal, or the selection) and nothing that needs templates.
    public static let roles: [AppDescriptor.Role] = [.editor, .terminal, .general]

    /// The apps of `config` that it defines, as lines to edit.
    /// - Parameter entries: Where each app the config writes is (`ConfigService.entryLocations(of: "app")`).
    public static func state(config: Config, entries: [String: EntryLocation], facts: any SystemFacts) -> AppsState {
        let builtIn = Set(KnownApps.all.map(\.id))
        let rows = config.apps.map { app -> AppRowState in
            let bundleID = app.installedBundleID(facts: facts)
            let usesTemplates: Bool
            if case .template = app.driver { usesTemplates = true } else { usesTemplates = false }
            return AppRowState(id: app.id, name: app.name, role: app.role, bundleIDs: app.bundleIDs, icon: (bundleID ?? app.bundleIDs.first).map(Icon.app), installed: bundleID != nil,
                               usesTemplates: usesTemplates, isKnownTerminal: KnownApps.terminal(bundleIDs: app.bundleIDs) != nil, origin: builtIn.contains(app.id) ? .replacesBuiltIn : .own, entry: entries[app.id])
        }
        var available: [String: String] = [:]
        for app in config.allApps {
            for bundleID in app.bundleIDs where available[bundleID.lowercased()] == nil { available[bundleID.lowercased()] = app.name }
        }
        var turnedOff: [String: String] = [:]
        for app in KnownApps.all where config.disabledApps.contains(app.id) {
            for bundleID in app.bundleIDs where turnedOff[bundleID.lowercased()] == nil { turnedOff[bundleID.lowercased()] = app.name }
        }
        let taken = Set(config.allApps.map(\.id)).union(KnownApps.all.map(\.id)).union(AgentLauncher.reservedWords)
            .union(config.allAgents.map(\.id)).union(KnownAgents.all.map(\.id)).union(config.newFile.templates.map(\.id)).union(NewFileTemplate.builtIn.map(\.id))
        return AppsState(rows: rows, available: available, turnedOff: turnedOff, takenIDs: taken)
    }

    private static func key(_ position: Int, _ field: String) -> String { "app.\(position).\(field)" }

    /// A change of the entry that holds `row`, on condition that the entry at that place is still `row`'s: a list that something else changed meanwhile is not changed in its place.
    private static func change(_ row: AppRowState, at entry: EntryLocation, _ operations: [ConfigOperation]) -> Change {
        Change(target: entry.target, operations: [.expectEntry(row.id, at: entry.position, in: "app")] + operations)
    }

    public static func changing(name: String, of row: AppRowState) -> Change? {
        let text = name.trimmingCharacters(in: .whitespaces)
        guard let entry = row.entry, !text.isEmpty, text != row.name else { return nil }
        return change(row, at: entry, [.set(key(entry.position, "name"), .string(text))])
    }

    /// What the app opens. An app that is started through templates, and a terminal that comes with Right Here, stay terminals.
    public static func changing(role: AppDescriptor.Role, of row: AppRowState) -> Change? {
        guard let entry = row.entry, !row.rolePinned, roles.contains(role), role != row.role else { return nil }
        return change(row, at: entry, [.set(key(entry.position, "role"), .string(role.rawValue))])
    }

    /// The entry taken out: an app of one's own is gone, and a built-in one that the entry replaced is the built-in one again.
    public static func removing(_ row: AppRowState) -> Change? {
        guard let entry = row.entry else { return nil }
        return change(row, at: entry, [.removeEntry(at: entry.position, from: "app")])
    }

    /// The name of the app that already offers `bundleID`, so that the same app is not added twice.
    public static func alreadyAvailable(bundleID: String, in state: AppsState) -> String? {
        state.available[bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    /// The name of the built-in app with `bundleID` that this Mac turns off: it is known, so it is not added again (as an editor, whatever it is): `disabled` in this Mac's own file brings it back.
    public static func turnedOff(bundleID: String, in state: AppsState) -> String? {
        state.turnedOff[bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    /// Whether `text` is a name the config accepts for an app: no control character, nothing that changes how it reads, and not longer than a name may be.
    public static func isPlainName(_ text: String) -> Bool {
        !ShellQuoting.containsControlCharacter(text) && !text.hasMisleadingCharacter(ignoringJoiners: true) && text.count <= ConfigBuilder.longestName
    }

    /// Whether `text` can be the bundle identifier of an app: letters, digits, dots, dashes and underscores, which is what the system gives one.
    public static func isBundleID(_ text: String) -> Bool {
        !text.isEmpty && text.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
    }

    /// A new app with a name, the bundle identifier it is looked for by and what it opens. The id is made from the name and is not one that is in use, so a built-in app is never replaced by
    /// accident. An app that is available already is not made again.
    /// - Parameters:
    ///   - alsoTaken: Ids that the files mention and the config does not show (an app the config left out for an error).
    ///   - alsoAvailable: The bundle identifiers of the apps that the files offer now, in lower case, when they may be newer than `state`.
    public static func creating(name: String, bundleID: String, role: AppDescriptor.Role, in state: AppsState, alsoTaken: Set<String> = [], alsoAvailable: Set<String> = []) -> (id: String, change: Change)? {
        let title = name.trimmingCharacters(in: .whitespaces), bundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, isBundleID(bundle), roles.contains(role), state.available[bundle.lowercased()] == nil, state.turnedOff[bundle.lowercased()] == nil,
              !alsoAvailable.contains(bundle.lowercased()) else { return nil }
        let taken = state.takenIDs.union(alsoTaken)
        let id = IDSlug.unique(IDSlug.make(from: title) ?? "app") { taken.contains($0) }
        var fields = [ConfigField("id", .string(id)), ConfigField("name", .string(title)), ConfigField("bundle_id", .string(bundle))]
        if role != .general { fields.append(ConfigField("role", .string(role.rawValue))) }
        return (id, Change(target: .shared, operations: [.addEntry(to: "app", fields: fields, at: nil)]))
    }
}
