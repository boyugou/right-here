import Foundation
import RightHereCore

/// What an edit did, or would do (a dry run): the one answer of the window, `rh config` and the MCP tool.
public struct ConfigChange: Sendable, Equatable, Encodable {
    public var target: ConfigTarget
    public var file: String
    /// What was asked, in a line.
    public var summary: String
    /// Whether the text is different from what it was.
    public var changed: Bool
    /// Whether the file was written: not for a dry run, and not when there was nothing to change.
    public var written: Bool
    /// The lines that differ, as a unified diff.
    public var diff: [String]
    /// What a person should read about the result: a warning the change brought, or a setting of the other file that decides on this Mac.
    public var warnings: [String]
    /// The digest of the text the change wrote (`nil` when it wrote nothing): an undo of exactly this change is held to it.
    public var afterDigest: String?
    /// The digest of the text the change replaced. A file can come back to the text a change wrote after another party changed it twice; the text that the last edit replaced is then not this
    /// change's, and an undo held to both digests refuses.
    public var beforeDigest: String?

    private enum CodingKeys: String, CodingKey { case target, file, summary, changed, written, diff, warnings }

    public init(target: ConfigTarget, file: String, summary: String, changed: Bool, written: Bool, diff: [String], warnings: [String], afterDigest: String? = nil, beforeDigest: String? = nil) {
        self.afterDigest = afterDigest
        self.beforeDigest = beforeDigest
        self.target = target
        self.file = file
        self.summary = summary
        self.changed = changed
        self.written = written
        self.diff = diff
        self.warnings = warnings
    }
}

/// Changes a config file the way a person asks for it, in the smallest way (`ConfigDocument`): under the lock of the config, against the file as it is at that
/// moment, and with the text before the edit kept for undo (`ConfigHistory`). ADR 0026.
public struct ConfigService: Sendable {
    public enum Failure: Error, LocalizedError, Equatable {
        /// There is no config yet: `rh setup` makes it, with what is installed, and a first run that is skipped by an edit would not.
        case noConfig(String)
        case unreadable(file: String, reason: String)
        case nothingToUndo(ConfigTarget)
        /// The file is not as the last edit left it, so undoing would also undo what was changed since.
        case changedSince(file: String)
        /// The file was changed while its text was being edited, so saving would throw that change away.
        case editedMeanwhile(file: String)
        /// The last edit was made by somebody else, and what an assistant may take back is its own.
        case notYours(ConfigTarget)
        /// The edit to take back is not the last one of the file any more: something else changed it after, and taking back the last one would be taking back that.
        case notTheLast(ConfigTarget)
        case noProposal(String)
        /// A change that waits is applied on the command line only after it was looked at (`rh config pending show`), and as the files were then.
        case notLookedAt(String)
        case editedSinceLooked(String)
        case tooManyProposals
        /// The lock of the config could not be taken (`.config.lock` is a link, or the folder cannot be written to), so two edits at once could not be told apart.
        case lockUnavailable(String)
        /// The file is read-only: whoever made it so meant it to be left alone.
        case readOnly(String)
        /// An assistant asked to take a change back, and what the files would say afterwards decides which program starts or whether an agent asks first: that waits for the person, as the same change would.
        case undoNeedsPerson(ConfigTarget, [String])

        public var errorDescription: String? {
            switch self {
            case .noConfig(let file):
                return "There is no config file at \(file.withControlCharactersEscaped) yet. Run `rh setup` to make one, then change it."
            case .unreadable(let file, let reason):
                return "Cannot read \(file.withControlCharactersEscaped): \(reason.withControlCharactersEscaped)"
            case .nothingToUndo(let target):
                return "There is no edit of \(target == .shared ? "config.toml" : "config.local.toml") to undo."
            case .changedSince(let file):
                return "\(file.withControlCharactersEscaped) was changed after the last edit, so undoing it would undo that change too. Look at it with `rh config show`, or undo anyway with --force."
            case .editedMeanwhile(let file):
                return "\(file.withControlCharactersEscaped) was changed while you were editing it, so nothing was saved. Copy what you wrote, reload the file, and make the change again."
            case .notYours(let target):
                return "The last edit of \(target == .shared ? "config.toml" : "config.local.toml") was not made by you, so it is not yours to take back. Ask the person."
            case .notTheLast(let target):
                return "\(target == .shared ? "config.toml" : "config.local.toml") was changed again after that edit, so it was not taken back: undoing the last edit would undo that one. `rh config history` lists them."
            case .noProposal(let id):
                return "There is no change waiting with the id \"\(id.withControlCharactersEscaped)\". `rh config pending` lists them."
            case .notLookedAt(let id):
                return "The change \"\(id.withControlCharactersEscaped)\" has not been looked at: `rh config pending show \(id.withControlCharactersEscaped)` says what it would do to the files as they are now, and `apply` then makes exactly that."
            case .editedSinceLooked(let id):
                return "The config changed after you looked at \"\(id.withControlCharactersEscaped)\", and what applying it would do may not be what you saw (an agent put in the menu meanwhile starts the same way). Look at it again with `rh config pending show \(id.withControlCharactersEscaped)`. Nothing was changed."
            case .tooManyProposals:
                return "\(ConfigProposals.keep) changes are waiting for the person already. Ask them to look at `rh config pending` before proposing more."
            case .lockUnavailable(let file):
                return "The lock \(file.withControlCharactersEscaped) cannot be taken (it is a link, or its folder cannot be written to), so the config was not changed: two edits made at once could not be told apart."
            case .readOnly(let file):
                return "\(file.withControlCharactersEscaped) is read-only, so it was not changed. Make it writable to let `rh config` and the window change it."
            case .undoNeedsPerson(let target, let keys):
                return "Taking back the last edit of \(target == .shared ? "config.toml" : "config.local.toml") would change what decides which program starts or whether an agent asks before it acts (\(keys.joined(separator: ", "))), "
                    + "and that waits for the person, as the same change would. They can take it back in the setup window or with `rh config undo`."
            }
        }
    }

    /// What came of a request: it was made, or it waits for the person.
    public enum Outcome: Sendable, Equatable {
        case applied(ConfigChange)
        /// A dry run of a change that would wait for the person: what it would do, and what in it needs them.
        case wouldWait([ConfigTrust.Approval], preview: ConfigChange)
        case proposed(ConfigProposal, preview: ConfigChange)
    }

    public struct HistoryItem: Sendable, Equatable, Encodable {
        public var time: Date
        public var actor: ConfigActor
        public var summary: String

        public init(time: Date, actor: ConfigActor, summary: String) {
            self.time = time
            self.actor = actor
            self.summary = summary
        }
    }

    public let paths: RHPaths
    private let now: @Sendable () -> Date
    private let environment: [String: String]
    private let realHome: URL

    /// `environment` and `realHome` are what `RealHomeGuard` reads; the process's own, but for a test of the guard.
    public init(paths: RHPaths, now: @escaping @Sendable () -> Date = { Date() }, environment: [String: String] = ProcessInfo.processInfo.environment,
                realHome: URL = LiveSystemFacts.realHomeDirectory) {
        self.paths = paths
        self.now = now
        self.environment = environment
        self.realHome = realHome
    }

    public func file(of target: ConfigTarget) -> URL {
        target == .shared ? paths.configFile : paths.localConfigFile
    }

    private var history: ConfigHistory { ConfigHistory(directory: paths.historyDirectory) }

    /// The edits of a file that can still be undone, newest first.
    public func history(of target: ConfigTarget = .shared) -> [HistoryItem] {
        entries(of: target).map { HistoryItem(time: $0.time, actor: $0.actor, summary: $0.summary) }
    }

    /// The history of this file of the config, newest first: the folder may hold the history of another (`RH_CONFIG`).
    private func entries(of target: ConfigTarget) -> [ConfigHistory.Entry] {
        history.entries(of: target, file: file(of: target).path)
    }

    // MARK: Reading

    /// The text of the file of `target` as a document, to look things up in. The shared file has to be there; the machine's own may be missing, which is an empty one.
    public func document(of target: ConfigTarget = .shared) throws -> ConfigDocument {
        let shared = try sharedText()
        if target == .shared { return ConfigDocument(shared) }
        return ConfigDocument(try localText() ?? "", validation: .overlay(over: shared))
    }

    /// What a file of the config holds, for an editor of its text: the text, and the digest to hand back with `apply(... unchangedSince:)`.
    public struct ConfigText: Sendable, Equatable {
        public var text: String
        public var digest: String
        public var exists: Bool

        public init(text: String, digest: String, exists: Bool) {
            self.text = text
            self.digest = digest
            self.exists = exists
        }
    }

    /// The text of a file of the config as it is now. The machine's own file may be missing, which is an empty text; the shared one has to be there (`noConfig`).
    public func text(of target: ConfigTarget = .shared) throws -> ConfigText {
        let shared = try sharedText()
        if target == .shared { return ConfigText(text: shared, digest: ConfigHistory.digest(shared), exists: true) }
        let local = try localText()
        return ConfigText(text: local ?? "", digest: ConfigHistory.digest(local ?? ""), exists: local != nil)
    }

    /// How a text for the file of `target` is read, for an editor that shows what is wrong with it as it is typed: the shared file on its own, the machine's own laid over the
    /// shared one as it is now.
    public func validation(for target: ConfigTarget = .shared) throws -> ConfigDocument.Validation {
        target == .shared ? .standalone : .overlay(over: try sharedText())
    }

    /// The file that decides a setting on this Mac: the machine's own file when it sets the key, else the shared one. An edit made there is the one that is seen here.
    /// - Parameter anchor: A key that the table of `path` stands on: the command of an agent of one's own is in the file that makes its table, and a key that goes to the other file
    ///   makes a table there that has no name or command. When this Mac's own file does not write `path` itself but does write the anchor, the key goes there with it.
    public func owner(of path: String, anchor: String? = nil) -> ConfigTarget {
        guard let text = try? localText() else { return .shared }
        let document = ConfigDocument(text)
        if document.rawValue(at: path) != nil { return .local }
        if let anchor, document.rawValue(at: anchor) != nil { return .local }
        return .shared
    }

    /// Where each entry of a list of tables (`preset`, `agent.claude.variant`) that the config shows is written, by its id: the file that holds the entry the config uses (this Mac's own when it
    /// writes it, else the shared one) and its place among the entries of that file, which is what an edit of one of its fields names it by. The merge of the two files says which entry that is
    /// (`ConfigLoadResult.entryOrigins`), so an entry that the other file replaces, that this Mac turns off, or that the config leaves out has no place here: the window edits what it shows. An
    /// entry that the file does not write at that place as a table of an array of tables with that id (an inline array, say) cannot be edited by place and has none either.
    /// - Parameter loaded: The config as it was just read; read again when it is not given.
    public func entryLocations(of table: String, in loaded: ConfigLoadResult? = nil) -> [String: EntryLocation] {
        let origins = (loaded ?? ConfigStore.load(paths: paths, withOrigins: true).result).entryOrigins[table] ?? []
        var found: [String: EntryLocation] = [:]
        var written: [ConfigTarget: [String?]] = [:]
        for origin in origins {
            guard let id = origin.id, found[id] == nil else { continue }
            if written[origin.target] == nil { written[origin.target] = (try? document(of: origin.target))?.entryIDs(in: table) ?? [] }
            guard let ids = written[origin.target], ids.indices.contains(origin.position - 1), ids[origin.position - 1] == id else { continue }
            found[id] = EntryLocation(target: origin.target, position: origin.position)
        }
        return found
    }

    /// Every id that an entry of a list of tables has or could be mistaken for: those of both files whether or not the config shows them (an entry it left out for an error, or that this Mac
    /// turns off, still has its id) and those this Mac's `disabled` names. A new entry takes none of them.
    public func entryIDsInUse(of table: String) -> Set<String> {
        var ids = Set<String>()
        for target in [ConfigTarget.shared, .local] {
            guard let document = try? document(of: target) else { continue }
            ids.formUnion(document.entryIDs(in: table).compactMap { $0 })
            ids.formUnion(document.parsedEntryIDs(in: table))
            if target == .local, let disabled = (try? document.elements(of: "disabled")) ?? nil { ids.formUnion(disabled) }
        }
        ids.formUnion((ConfigStore.load(paths: paths, withOrigins: true).result.entryOrigins[table] ?? []).compactMap(\.id))
        return ids
    }

    /// Every id that an app, a new-file template or an agent has, or could be mistaken for: those the files mention (`entryIDsInUse`, `agentIDsInUse`) and those that come with Right Here. `disabled` in
    /// this Mac's own file is one list of ids for the three kinds, so a new entry of one kind that takes an id of another would be turned off with it.
    public func disableableIDsInUse() -> Set<String> {
        entryIDsInUse(of: "app").union(entryIDsInUse(of: "new_file.template")).union(agentIDsInUse())
            .union(KnownApps.all.map(\.id)).union(NewFileTemplate.builtIn.map(\.id)).union(KnownAgents.all.map(\.id))
    }

    /// The apps the files offer, by bundle identifier in lower case, whether or not this Mac turns them off or the window has read them: the built-in ones, and those of the merged config and of the
    /// shared file alone. A new app is not made from an application that is among them.
    public func appsAvailable() -> [String: String] {
        var found: [String: String] = [:]
        let loaded = ConfigStore.load(paths: paths).config
        for app in KnownApps.all + loaded.allApps + ConfigStore.sharedConfig(paths: paths).apps {
            for bundleID in app.bundleIDs where found[bundleID.lowercased()] == nil { found[bundleID.lowercased()] = app.name }
        }
        return found
    }

    /// The ids of the entries that a file writes and the config does not show (an entry this Mac drops: its preset names an agent that it turns off).
    public func hiddenEntryIDs(of table: String, in target: ConfigTarget, loaded: ConfigLoadResult) -> Set<String> {
        let shown = Set((loaded.entryOrigins[table] ?? []).compactMap(\.id))
        return ((try? document(of: target))?.parsedEntryIDs(in: table) ?? []).subtracting(shown)
    }

    public func presetEntries(in loaded: ConfigLoadResult? = nil) -> [String: PresetRowState.Entry] { entryLocations(of: "preset", in: loaded) }

    public func presetIDsInUse() -> Set<String> { entryIDsInUse(of: "preset") }

    /// Every id of an agent that a file of the config mentions: a table (whether or not this Mac's own file turns the agent off) and an id that file disables. A new agent takes none of them.
    public func agentIDsInUse() -> Set<String> {
        var ids = Set<String>()
        if let shared = try? sharedText() { ids.formUnion(ConfigDocument(shared).tableIDs(of: "agent")) }
        if let local = (try? localText()) ?? nil {
            let document = ConfigDocument(local)
            ids.formUnion(document.tableIDs(of: "agent"))
            if let disabled = (try? document.elements(of: "disabled")) ?? nil { ids.formUnion(disabled) }
        }
        return ids
    }

    /// What the file that decides the list of text `key` on this Mac writes for it: the items in order, or `nil` when it does not write the list (or does not read). A window that
    /// changes the list by place holds the change to this, so that something that changed the file meanwhile is not mistaken for what was shown.
    public func listed(_ key: String) -> [String]? {
        listed(key, in: owner(of: key))
    }

    /// The same for the file that holds an entry of a list of tables, whose fields it is the one to ask.
    public func listed(_ key: String, in target: ConfigTarget) -> [String]? {
        (try? document(of: target).elements(of: key)) ?? nil
    }

    /// What the file that holds each start option of `agent` writes for its `arguments`, by the id of the start option (`entries` says where each is).
    public func variantArguments(of agent: String, entries: [String: EntryLocation]) -> [String: [String]] {
        var found: [String: [String]] = [:]
        for (id, entry) in entries {
            if let items = listed("\(AgentVariants.table(of: agent)).\(entry.position).arguments", in: entry.target) { found[id] = items }
        }
        return found
    }

    /// The changes a request asks for, on the file as it is now. For looking: a change is made with `apply(_ request:)` or `submit(_ request:)`, which look at the file under the lock, so that
    /// an item named in the request is the item that is there when the change is made.
    public func operations(for request: ConfigRequest, target: ConfigTarget = .shared) throws -> [ConfigOperation] {
        let merged = ConfigStore.load(paths: paths).config
        let seeds: (String) -> [ConfigOperation] = { key in
            // The built-in templates go out with the first template of a config that defines none, as the window writes them out: the config would otherwise lose them on every Mac.
            key == "new_file.template" && !merged.newFile.definesTemplates ? NewFileOptions.builtInEntries(localizer: merged.localizer) : []
        }
        return try request.operations(in: try document(of: target), defaultList: defaultList(for: target, merged: merged), seedEntries: seeds)
    }

    /// The lists a request may change while the file it goes to does not write them, as they are for whoever reads that file: for the shared file, what another Mac gets from it alone (the
    /// default list of the shared file's own agents), and for this Mac's own file, the list this Mac shows (what the shared file writes, else the default), so that the first change adds to
    /// the list and does not replace it.
    private func defaultList(for target: ConfigTarget, merged: Config) -> (String) -> [String]? {
        if target == .local { return { ConfigDefaults.shown(for: $0, config: merged) } }
        let shared = ConfigStore.sharedConfig(paths: paths)
        return { ConfigDefaults.list(for: $0, config: shared) }
    }

    /// Makes what a request asks for. The item or the entry it names is looked for under the lock, in the file as it is then: two requests made at the same time each change what they
    /// meant, whichever comes first.
    public func apply(_ request: ConfigRequest, target: ConfigTarget = .shared, actor: ConfigActor, dryRun: Bool = false) throws -> ConfigChange {
        try locked { try applyLocked(try operations(for: request, target: target), target: target, actor: actor, dryRun: dryRun) }
    }

    // MARK: Editing

    /// Makes the change, or with `dryRun` says what it would do. Throws `ConfigDocument.EditError` for a change that cannot be made (the text says why) and `Failure`.
    public func apply(_ operation: ConfigOperation, target: ConfigTarget = .shared, actor: ConfigActor, dryRun: Bool = false) throws -> ConfigChange {
        try apply([operation], target: target, actor: actor, dryRun: dryRun)
    }

    /// Several changes as one edit: each is made on what the one before left, and either all of them are written (one entry of the history, one undo) or none.
    ///
    /// With `unchangedSince`, the SHA-256 of the text that was read (`ConfigText.digest`), the change is made only when the file is still that text: whoever edits a text for a
    /// while must not save over a change that was made meanwhile.
    public func apply(_ operations: [ConfigOperation], target: ConfigTarget = .shared, actor: ConfigActor, dryRun: Bool = false, unchangedSince digest: String? = nil) throws -> ConfigChange {
        try locked { try applyLocked(operations, target: target, actor: actor, dryRun: dryRun, unchangedSince: digest) }
    }

    /// Takes the lock of the config for `body`. Before the lock file is made, which is a write too, a process a test started is kept from the real home; and there is no
    /// lock for a config that is not there, which would make its folder.
    private func locked<Result>(_ body: () throws -> Result) throws -> Result {
        try RealHomeGuard.checkWriting(paths.configDirectory, environment: environment, realHome: realHome)
        _ = try sharedText()
        let lock = try FileLock.acquireNow(paths.configLockFile, timeout: .seconds(5))
        // A lock that could not be taken is not an error of the lock (`FileLock` says nothing of it): an edit made without it is one that two at once can lose.
        guard lock.isHeld else { throw Failure.lockUnavailable(paths.configLockFile.path) }
        defer { lock.release() }
        return try body()
    }

    private func applyLocked(_ operations: [ConfigOperation], target: ConfigTarget, actor: ConfigActor, dryRun: Bool, unchangedSince digest: String? = nil) throws -> ConfigChange {
        let file = file(of: target)
        let shared = try sharedText()
        let overlay = try localText()
        let current = target == .shared ? shared : (overlay ?? "")
        if let digest, ConfigHistory.digest(current) != digest { throw Failure.editedMeanwhile(file: file.path) }
        var edited = ConfigDocument(current, validation: target == .shared ? .standalone : .overlay(over: shared))
        for operation in operations { edited = try operation.apply(to: edited) }
        let editedText = edited.text
        let changed = editedText != current
        // What the two files make together has to read, not only the file that was changed: this Mac's own file may still name what a change of the shared file takes out (a key of an agent that is
        // gone, a preset that uses it), and the shared file may name what a change of this Mac's own file takes out or turns into something else (an app that is a terminal no more, an editor
        // that is gone), and the config would then have an error that no editor is open to show.
        if changed {
            let name = paths.localConfigFile.lastPathComponent
            func problems(shared: String, overlay: String?) -> Set<String> {
                Set(ConfigLayers.load(base: .text(shared), local: overlay.map { .text($0) } ?? .absent, overlayName: name).diagnostics.filter { $0.severity == .error }
                    .map { "\($0.file ?? file.lastPathComponent): \($0.path.isEmpty ? "" : "[\($0.path)] ")\($0.message)" })
            }
            let after = target == .shared ? problems(shared: editedText, overlay: overlay) : problems(shared: shared, overlay: editedText)
            if let new = after.subtracting(problems(shared: shared, overlay: overlay)).sorted().first { throw ConfigDocument.EditError.wouldBeInvalid(new) }
        }
        let summary = Self.summary(of: operations)
        var change = ConfigChange(target: target, file: file.path, summary: summary, changed: changed, written: false, diff: LineDiff.unified(from: current, to: editedText),
                                  warnings: warnings(for: operations, target: target,
                                                     before: (shared, overlay), after: (target == .shared ? editedText : shared, target == .local ? editedText : overlay)))
        guard changed, !dryRun else { return change }
        let entry = ConfigHistory.Entry(time: now(), actor: actor, target: target, summary: summary, before: current, afterDigest: ConfigHistory.digest(editedText),
                                        file: file.path, existed: target == .shared || overlay != nil)
        // The text before is kept first: an edit that is written without it could not be undone.
        let stored = try history.record(entry)
        do {
            try write(editedText, to: file)
        } catch {
            history.remove(named: stored)
            throw error
        }
        history.prune(of: target, file: file.path)
        change.written = true
        change.afterDigest = ConfigHistory.digest(editedText)
        change.beforeDigest = ConfigHistory.digest(current)
        return change
    }

    // MARK: Changes that wait for the person

    private var proposals: ConfigProposals { ConfigProposals(directory: paths.proposalsDirectory) }

    /// What a request from an AI assistant comes to: a change that decides which program starts, or whether an agent asks first, is not made on its say-so but proposed
    /// (`ConfigTrust`), and anything else is made like `apply`. Whoever else asks (`.cli`, `.window`) is the person, or a shell the person gave an agent, and is not stopped.
    public func submit(_ operations: [ConfigOperation], target: ConfigTarget = .shared, actor: ConfigActor, dryRun: Bool = false) throws -> Outcome {
        guard actor == .mcp else { return .applied(try apply(operations, target: target, actor: actor, dryRun: dryRun)) }
        return try locked { try submitLocked(operations, target: target, actor: actor, dryRun: dryRun) }
    }

    /// The same for what a request asks, which is turned into changes under the lock (`apply(_ request:)`).
    public func submit(_ request: ConfigRequest, target: ConfigTarget = .shared, actor: ConfigActor, dryRun: Bool = false) throws -> Outcome {
        guard actor == .mcp else { return .applied(try apply(request, target: target, actor: actor, dryRun: dryRun)) }
        return try locked { try submitLocked(try operations(for: request, target: target), target: target, actor: actor, dryRun: dryRun) }
    }

    private func submitLocked(_ operations: [ConfigOperation], target: ConfigTarget, actor: ConfigActor, dryRun: Bool) throws -> Outcome {
        var approvals = ConfigTrust.approvals(for: operations)
        // A whole text already says that anything may be in it.
        if !approvals.contains(where: { $0.key == "*" }) {
            for effect in try effectApprovals(of: operations, target: target) where !approvals.contains(where: { $0.key == effect.key }) { approvals.append(effect) }
        }
        // A change that cannot be made is refused now, not when the person looks at it.
        let preview = try applyLocked(operations, target: target, actor: actor, dryRun: true)
        guard !approvals.isEmpty, preview.changed else { return .applied(try applyLocked(operations, target: target, actor: actor, dryRun: dryRun)) }
        if dryRun { return .wouldWait(approvals, preview: preview) }
        let waiting = proposals.all(now: now())
        // The same change proposed again is the proposal that is there.
        let guarded = try identity(of: operations, target: target) + operations
        if let same = waiting.first(where: { $0.operations == guarded && $0.target == target }) { return .proposed(same, preview: preview) }
        guard waiting.count < ConfigProposals.keep else { throw Failure.tooManyProposals }
        // What it names by its place it names for good: the person looks at a card, and the entry at that place when they press Apply may be another one.
        let proposal = ConfigProposal(id: String(UUID().uuidString.prefix(8)).lowercased(), time: now(), actor: actor, target: target,
                                      operations: guarded, summary: Self.summary(of: operations), approvals: approvals)
        try proposals.store(proposal)
        return .proposed(proposal, preview: preview)
    }

    /// The checks that keep a stored change with what it was made for: the list it takes an item out of or moves one in is the list that was there, and an entry it changes by its
    /// place (`app.2.bundle_id`) is the one with the id it had.
    private func identity(of operations: [ConfigOperation], target: ConfigTarget) throws -> [ConfigOperation] {
        let document = try self.document(of: target)
        var checks: [ConfigOperation] = []
        func add(_ check: ConfigOperation) { if !checks.contains(check) { checks.append(check) } }
        func entry(of path: String) {
            let segments = path.split(separator: ".").map(String.init)
            for (index, segment) in segments.enumerated() where index > 0 {
                guard let position = Int(segment) else { continue }
                let table = segments[0..<index].joined(separator: ".")
                if let id = document.entryID(at: position, in: table) { add(.expectEntry(id, at: position, in: table)) }
            }
        }
        for operation in operations {
            switch operation {
            case .set(let path, _), .unset(let path):
                entry(of: path)
            case .remove(_, let path), .replace(_, let path, _), .move(_, _, let path):
                add(.expect((try? document.elements(of: path)) ?? nil, in: path))
            case .insert(_, let path, let position):
                if position != nil { add(.expect((try? document.elements(of: path)) ?? nil, in: path)) }
            case .removeEntry(let position, let table):
                if let id = document.entryID(at: position, in: table) { add(.expectEntry(id, at: position, in: table)) }
            case .moveEntry(let from, _, let table):
                if let id = document.entryID(at: from, in: table) { add(.expectEntry(id, at: from, in: table)) }
            case .addEntry, .addTable, .removeTable, .replaceText, .expect, .expectEntry:
                break
            }
        }
        return checks
    }

    /// What the config says before the edit and after it: the two files laid over each other.
    private func configs(of operations: [ConfigOperation], target: ConfigTarget) throws -> (before: Config, after: Config) {
        let shared = try sharedText()
        let overlay = try localText()
        var edited = ConfigDocument(target == .shared ? shared : (overlay ?? ""), validation: target == .shared ? .standalone : .overlay(over: shared))
        for operation in operations { edited = try operation.apply(to: edited) }
        func config(shared: String, local: String?) -> Config {
            ConfigLayers.load(base: .text(shared), local: local.map(ConfigSource.text) ?? .absent, overlayName: paths.localConfigFile.lastPathComponent).config
        }
        return (config(shared: shared, local: overlay), config(shared: target == .shared ? edited.text : shared, local: target == .local ? edited.text : overlay))
    }

    /// What the config says now and what it would say if the file of `target` had `text` (`nil`: no file), the two files laid over each other.
    private func configs(replacing target: ConfigTarget, with text: String?) throws -> (before: Config, after: Config) {
        let shared = try sharedText()
        let overlay = try localText()
        func config(shared: String, local: String?) -> Config {
            ConfigLayers.load(base: .text(shared), local: local.map(ConfigSource.text) ?? .absent, overlayName: paths.localConfigFile.lastPathComponent).config
        }
        return (config(shared: shared, local: overlay), config(shared: target == .shared ? (text ?? shared) : shared, local: target == .local ? text : overlay))
    }

    /// What the edit would do to the agents once it is made, as `ConfigTrust` reads it (`approvals(changingFrom:to:)`): the two files laid over each other before and after.
    private func effectApprovals(of operations: [ConfigOperation], target: ConfigTarget) throws -> [ConfigTrust.Approval] {
        let both = try configs(of: operations, target: target)
        return ConfigTrust.approvals(changingFrom: both.before, to: both.after)
    }

    /// The agents that the edit would make start without their permission prompts, and did not: what the person is asked about before a change of the window is made (the window is the person,
    /// so nothing stops it, but it does not take the yes for granted). Empty for an edit that cannot be made, which is refused when it is tried.
    public func looseningEffects(of operations: [ConfigOperation], target: ConfigTarget) -> [PromptEffects.Entry] {
        guard let both = try? configs(of: operations, target: target) else { return [] }
        return PromptEffects.newlyWithoutAsking(from: both.before, to: both.after)
    }

    /// A stored proposal as the person is shown it: what it says it does and what it waits for are worked out again from its operations. A file in the proposals folder is written by
    /// anything that runs as the person, and its own summary and list of approvals are only what it says of itself.
    private func verified(_ proposal: ConfigProposal) -> ConfigProposal {
        var copy = proposal
        copy.summary = Self.summary(of: proposal.operations)
        var approvals = ConfigTrust.approvals(for: proposal.operations)
        if !approvals.contains(where: { $0.key == "*" }), let effects = try? effectApprovals(of: proposal.operations, target: proposal.target) {
            for effect in effects where !approvals.contains(where: { $0.key == effect.key }) { approvals.append(effect) }
        }
        // What turning the prompts off comes to is said by name: the agents that would start without asking, and with which flag. The card of "switch the prompts off" that does not say which
        // agents (an assistant may have put one in the menu, or may before the person presses Apply) asks for a yes that names nothing.
        let loosened = looseningEffects(of: proposal.operations, target: proposal.target)
        if !loosened.isEmpty {
            let said = loosened.map { "\($0.name) would start with \($0.flag)" }.joined(separator: "; ")
            // The window writes the reason in its language and these after it: names and flags, which are the same in every language.
            let pairs = loosened.map { "\($0.name) \($0.flag)" }.joined(separator: "; ")
            approvals = approvals.map { $0.key.hasSuffix(".bypass_permissions") ? ConfigTrust.Approval(key: $0.key, reason: "\($0.reason): \(said)", effect: pairs) : $0 }
        }
        copy.approvals = approvals
        return copy
    }

    /// What identifies the two files of the config as they are now, for a change that is held to be made on the files that were looked at: a change of the other file counts as well.
    private func filesDigest() throws -> String {
        ConfigHistory.digest(try sharedText() + "\u{0}" + (try localText() ?? "\u{0}"))
    }

    /// The agents that making a stored proposal would start without their permission prompts, as the window asks before it applies one.
    public func looseningEffects(ofProposal id: String) -> [PromptEffects.Entry] {
        guard let proposal = proposals.proposal(id, now: now()) else { return [] }
        return looseningEffects(of: proposal.operations, target: proposal.target)
    }

    /// The changes that wait for the person, newest first.
    public func pending() -> [ConfigProposal] {
        proposals.all(now: now()).map(verified)
    }

    /// What applying a proposal would do to the file as it is now, and the digest of the two files of the config: a person who has looked at this applies it with `approve(... unchangedSince:)`
    /// and that digest, and the change is made only if the files are still the ones that were looked at (a change of this Mac's own file can widen what a yes to the shared file's change comes to).
    public func preview(proposal id: String, recordingLook: Bool = false) throws -> (proposal: ConfigProposal, change: ConfigChange, digest: String) {
        try locked {
            guard var stored = proposals.proposal(id, now: now()) else { throw Failure.noProposal(id) }
            let proposal = verified(stored)
            let digest = try filesDigest()
            // The command line has no screen to hold what was shown: the proposal keeps the digest, and `approve(afterLooking:)` is held to it.
            if recordingLook {
                stored.shownDigest = digest
                try proposals.store(stored)
            }
            return (proposal, try applyLocked(proposal.operations, target: proposal.target, actor: proposal.actor, dryRun: true), digest)
        }
    }

    /// Makes a proposal's change, as `actor` (the person's side: the window or the command line), and forgets the proposal. A change that no longer applies to the file as it
    /// is (it was edited since) is refused and the proposal stays, to be dismissed. With `unchangedSince`, the digest `preview(proposal:)` gave, it is made only when the file is
    /// still the text that was looked at: a change by position would otherwise land on whatever stands there now.
    /// With `afterLooking`, the command line's way: it is made only when `preview(proposal:recordingLook:)` was run for it and the files are still as they were then.
    public func approve(_ id: String, actor: ConfigActor = .cli, unchangedSince digest: String? = nil, afterLooking: Bool = false) throws -> ConfigChange {
        try locked {
            guard let proposal = proposals.proposal(id, now: now()) else { throw Failure.noProposal(id) }
            if let digest, try filesDigest() != digest { throw Failure.editedMeanwhile(file: file(of: proposal.target).path) }
            if afterLooking {
                guard let shown = proposal.shownDigest else { throw Failure.notLookedAt(id) }
                guard try filesDigest() == shown else { throw Failure.editedSinceLooked(id) }
            }
            let change = try applyLocked(proposal.operations, target: proposal.target, actor: actor, dryRun: false)
            proposals.remove(id)
            return change
        }
    }

    public func dismiss(_ id: String) throws {
        try locked {
            guard proposals.proposal(id, now: now()) != nil else { throw Failure.noProposal(id) }
            proposals.remove(id)
        }
    }

    /// Puts the file back as it was before the last edit made through this service, when it is still as that edit left it (or with `force`). `madeBy` limits it to an edit
    /// that somebody made: an assistant takes back its own and not the person's.
    ///
    /// With `expecting`, the digest a change reported (`ConfigChange.afterDigest`), it takes back that change and nothing else: when the last edit is another one it is refused. A banner that
    /// says "moved X" has to undo the move and not whatever was done last. With `replacing` as well (`ConfigChange.beforeDigest`) the last edit has to have replaced the text that this one did: a
    /// file that someone else changed and changed back is not the change that was made.
    public func undo(target: ConfigTarget = .shared, force: Bool = false, dryRun: Bool = false, madeBy actor: ConfigActor? = nil, expecting digest: String? = nil, replacing before: String? = nil) throws -> ConfigChange {
        try locked {
            let file = file(of: target)
            guard let entry = entries(of: target).first else { throw Failure.nothingToUndo(target) }
            if let actor, entry.actor != actor { throw Failure.notYours(target) }
            if let digest, entry.afterDigest != digest { throw Failure.notTheLast(target) }
            if let before, ConfigHistory.digest(entry.before) != before { throw Failure.notTheLast(target) }
            let current: String
            switch ConfigStore.text(of: file) {
            case .absent: current = ""
            case .problem(let reason): throw Failure.unreadable(file: file.path, reason: reason)
            case .text(let text): current = Self.lineFeeds(text)
            }
            guard force || ConfigHistory.digest(current) == entry.afterDigest else { throw Failure.changedSince(file: file.path) }
            // An assistant takes a change back as it makes one: what the two files would say afterwards is held to the same rule. A change made to the other file since (the person turned the
            // prompts off) can make the text of this file mean something that nobody approved.
            if actor == .mcp {
                let both = try configs(replacing: target, with: entry.existed ? entry.before : nil)
                let waits = ConfigTrust.approvals(changingFrom: both.before, to: both.after)
                if !waits.isEmpty { throw Failure.undoNeedsPerson(target, waits.map(\.key)) }
            }
            var change = ConfigChange(target: target, file: file.path, summary: "undo: " + entry.summary, changed: current != entry.before, written: false,
                                      diff: LineDiff.unified(from: current, to: entry.before), warnings: [])
            guard !dryRun else { return change }
            if entry.existed {
                try write(entry.before, to: file)
            } else {
                // The edit made the file: taking it back leaves no file, and not an empty one.
                try RealHomeGuard.checkWriting(file, environment: environment, realHome: realHome)
                try? FileManager.default.removeItem(at: file.resolvingSymlinksInPath())
            }
            history.remove(entry)
            change.written = true
            return change
        }
    }

    /// The line the history and the answer give for a list of changes.
    static func summary(of operations: [ConfigOperation]) -> String {
        let text = operations.filter { !$0.isCheck }.map(\.summary).joined(separator: "; ")
        return text.count > 160 ? String(text.prefix(157)) + "..." : text
    }

    // MARK: Reading and writing

    /// The shared file's text; an edit is never the first thing that makes the config (`rh setup` is).
    private func sharedText() throws -> String {
        switch ConfigStore.text(of: paths.configFile) {
        case .absent: throw Failure.noConfig(paths.configFile.path)
        case .problem(let reason): throw Failure.unreadable(file: paths.configFile.path, reason: reason)
        case .text(let text): return Self.lineFeeds(text)
        }
    }

    private func localText() throws -> String? {
        switch ConfigStore.text(of: paths.localConfigFile) {
        case .absent: return nil
        case .problem(let reason): throw Failure.unreadable(file: paths.localConfigFile.path, reason: reason)
        case .text(let text): return Self.lineFeeds(text)
        }
    }

    /// Whether every line break of a text is a CRLF (and there is one). Such a file is edited with line feeds and written back with CRLF: its comments and lines are what they were, and no
    /// line of another ending is put among them.
    static func usesCRLF(_ raw: String) -> Bool {
        var previous: UInt8 = 0
        var sawOne = false
        for byte in raw.utf8 {
            if byte == 0x0A {
                guard previous == 0x0D else { return false }
                sawOne = true
            }
            previous = byte
        }
        return sawOne
    }

    /// The text of a file as an edit reads it: a file that uses CRLF throughout is read as lines ended by line feeds.
    static func lineFeeds(_ raw: String) -> String {
        usesCRLF(raw) ? raw.replacingOccurrences(of: "\r\n", with: "\n") : raw
    }

    /// Through a link: a config kept in a dotfiles repository stays a link, and the file it points to is the one that changes.
    /// The file keeps the byte order mark and the line endings it has (an edit is read as lines ended by line feeds), and a file that was made read-only is left alone.
    private func write(_ text: String, to file: URL) throws {
        try RealHomeGuard.checkWriting(file, environment: environment, realHome: realHome)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = file.resolvingSymlinksInPath()
        let existing = try? Data(contentsOf: target)
        if existing != nil, !FileManager.default.isWritableFile(atPath: target.path) { throw Failure.readOnly(file.path) }
        var out = text
        if let existing, Self.usesCRLF(String(decoding: existing, as: UTF8.self)) {
            out = out.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        }
        var data = Data(out.utf8)
        if let existing, existing.starts(with: [0xEF, 0xBB, 0xBF]), !out.hasPrefix("\u{FEFF}") { data = Data([0xEF, 0xBB, 0xBF]) + data }
        try AtomicFile.write(data, to: target)
    }

    /// What is worth reading after the edit: the warnings the change brought (the ones the files had before are `rh config validate`'s to say), and a setting of the
    /// per-machine overlay that decides on this Mac whatever the shared file says.
    private func warnings(for operations: [ConfigOperation], target: ConfigTarget, before: (shared: String, local: String?), after: (shared: String, local: String?)) -> [String] {
        func warned(_ texts: (shared: String, local: String?)) -> [ConfigDiagnostic] {
            let result = ConfigLayers.load(base: .text(texts.shared), local: texts.local.map(ConfigSource.text) ?? .absent, overlayName: paths.localConfigFile.lastPathComponent)
            return result.diagnostics.filter { $0.severity == .warning }
        }
        // A line number moves when something is added above it, so a warning is the same one when its file, setting and sentence are.
        func identity(_ diagnostic: ConfigDiagnostic) -> String { "\(diagnostic.file ?? "")|\(diagnostic.path)|\(diagnostic.message)" }
        let known = Set(warned(before).map(identity))
        var found = warned(after).filter { !known.contains(identity($0)) }.map { $0.summary(file: paths.configFile) }
        if target == .shared, let local = after.local {
            let overlay = ConfigDocument(local)
            let localName = paths.localConfigFile.lastPathComponent
            for key in operations.flatMap(\.settingPaths) {
                // A path with a place in it (`app.1.name`) names the first entry of a file, which is another entry in the other file: it is the id of the entry that says whether the other file has it.
                if Self.entryPlace(of: key) != nil { continue }
                if overlay.rawValue(at: key) != nil {
                    found.append("note: \(localName) sets \(key) as well, and it decides on this Mac: the change reaches other Macs, not this one (--local changes this Mac's own setting).")
                }
            }
            // An entry that this Mac's own file writes too (the same id) is the one that decides here.
            let shared = ConfigDocument(before.shared)
            var noted = Set<String>()
            for operation in operations {
                guard let place = Self.entryPlace(of: operation) else { continue }
                let ids = shared.entryIDs(in: place.table)
                guard place.position >= 1, place.position <= ids.count, let id = ids[place.position - 1],
                      overlay.parsedEntryIDs(in: place.table).contains(id), noted.insert("\(place.table) \(id)").inserted else { continue }
                found.append("note: \(localName) has an entry \"\(id.withControlCharactersEscaped)\" in [[\(place.table)]] as well, and it decides on this Mac: the change reaches other Macs, not this one (--local changes this Mac's own setting).")
            }
        }
        return found
    }

    /// The table and the place (from 1) of the entry that a path or an operation is about, or `nil` when it is about no entry.
    private static func entryPlace(of path: String) -> (table: String, position: Int)? {
        let segments = path.split(separator: ".").map(String.init)
        guard let index = segments.indices.first(where: { $0 > 0 && Int(segments[$0]) != nil }), let position = Int(segments[index]) else { return nil }
        return (segments[..<index].joined(separator: "."), position)
    }

    private static func entryPlace(of operation: ConfigOperation) -> (table: String, position: Int)? {
        switch operation {
        case .removeEntry(let position, let table): (table, position)
        case .moveEntry(let from, _, let table): (table, from)
        case .set(let path, _), .unset(let path): entryPlace(of: path)
        default: nil
        }
    }
}
