import Foundation

/// The app an action uses when it does not name one: the default the config sets, else the first installed one in a
/// fixed preference order. The planner, the menu and the registry all ask here, so they cannot disagree about it.
///
/// A default the config sets that is not installed on this Mac (a config shared between Macs names an app only one of them
/// has) counts as if the config had not set one: the first installed app of the role is used, and `substitution` says so.
/// Only the default falls back. An action that names an app (`open.terminal@iterm`, an agent's own terminal) keeps saying
/// that the app is not installed.
public struct DefaultApps: Sendable {
    public let config: Config
    public let facts: any SystemFacts

    public init(config: Config, facts: any SystemFacts) {
        self.config = config
        self.facts = facts
    }

    /// The configured default when it is installed, else the first installed app of the role in the preference order. When
    /// nothing of the role is installed the configured default is returned as it is, for the action to say it is missing.
    public func resolve(role: AppDescriptor.Role, configured: String?) throws(PlanError) -> AppDescriptor {
        let named = try configuredApp(configured, role: role)
        if let named, isInstalled(named) { return named }
        if let first = candidates(for: role).first(where: isInstalled) { return first }
        if let named { return named }
        throw PlanError.noDefaultApp(role)
    }

    /// The terminal an action opens when it names one (`open.terminal@ghostty`) or none: the one named, which has to be a
    /// terminal (an id that names an editor is as unknown as one that names nothing), else the default as `resolve` has it.
    /// The planner and the registry both ask here, so a menu offers what `rh run` can do and says why it cannot in the same
    /// words. Whether the app is installed is left to the caller.
    public func terminal(id: String?) throws(PlanError) -> AppDescriptor {
        guard let id else { return try resolve(role: .terminal, configured: config.terminal) }
        guard let app = config.terminalApp(id: id) else { throw PlanError.unknownTerminal(id) }
        return app
    }

    /// The terminal an agent is typed into when none is named: the configured default when it is installed, as it is, else
    /// the first installed one that can run a command. A folder-only terminal (iTerm, kitty and the like) is a fine place to
    /// open a folder but would make every agent entry fail while Terminal.app sits next to it.
    public func commandTerminal() throws(PlanError) -> AppDescriptor {
        let named = try configuredApp(config.terminal, role: .terminal)
        if let named, isInstalled(named) { return named }
        let capable = candidates(for: .terminal).first { app in
            guard let bundleID = app.installedBundleID(facts: facts) else { return false }
            let adapter = TerminalAdapters.adapter(for: app)
            return adapter.supportsCommands && adapter.commandBlocker(bundleID: bundleID, facts: facts) == nil
        }
        if let capable { return capable }
        // Nothing can run a command: the first installed terminal is still the answer, and starting an agent in it says why not.
        return try resolve(role: .terminal, configured: config.terminal)
    }

    /// A default the config chose that is not installed, and the app used in its place.
    public struct Substitution: Sendable, Equatable {
        public let wanted: AppDescriptor
        public let used: AppDescriptor

        public init(wanted: AppDescriptor, used: AppDescriptor) {
            self.wanted = wanted
            self.used = used
        }

        /// What `rh` says about it, and what the doctor's catalog sentence says in English (a test holds the two together).
        public var sentence: String { "\(wanted.name) is not installed; \(used.name) is used instead." }
    }

    /// Whether the default of `role` the config sets is an app that is not installed here while another one is used instead.
    /// - Parameter typing: For a terminal, whether the question is about typing a command (what an agent entry does) and not
    ///   about opening a folder: the terminal that can run a command is not always the one that opens a folder.
    public func substitution(role: AppDescriptor.Role, typing: Bool = false) -> Substitution? {
        let configured = role == .terminal ? config.terminal : config.editor
        guard let configured, let wanted = try? app(named: configured, role: role), !isInstalled(wanted) else { return nil }
        let used = typing ? try? commandTerminal() : try? resolve(role: role, configured: configured)
        guard let used, used.id != wanted.id, isInstalled(used) else { return nil }
        return Substitution(wanted: wanted, used: used)
    }

    /// The apps of a role that have a rank, best first. An app the config gave another role than its built-in id has is
    /// not a candidate for this one.
    static func ranked(_ apps: [AppDescriptor], role: AppDescriptor.Role) -> [AppDescriptor] {
        apps.filter { $0.role == role }.compactMap { app in app.defaultRank.map { (app: app, rank: $0) } }.sorted { $0.rank < $1.rank }.map(\.app)
    }

    /// The apps of a role in the order they are tried: the ranked ones, then the config's own that have no rank.
    private func candidates(for role: AppDescriptor.Role) -> [AppDescriptor] {
        Self.ranked(config.allApps, role: role) + config.apps.filter { $0.role == role && $0.defaultRank == nil }
    }

    private func isInstalled(_ app: AppDescriptor) -> Bool {
        app.installedBundleID(facts: facts) != nil
    }

    private func configuredApp(_ id: String?, role: AppDescriptor.Role) throws(PlanError) -> AppDescriptor? {
        guard let id else { return nil }
        return try app(named: id, role: role)
    }

    /// The app the config names as default, installed or not. The config can redefine a built-in id with another role; a
    /// terminal that is now an editor (or the reverse) is not what the setting asked for, and `rh actions` already says so.
    private func app(named id: String, role: AppDescriptor.Role) throws(PlanError) -> AppDescriptor {
        guard let app = config.app(id: id) else { throw PlanError.unknownApp(id) }
        if role == .terminal, app.role != .terminal { throw PlanError.notATerminal(app) }
        if role == .editor, app.role == .terminal {
            throw PlanError.unsupported("\(app.name) is a terminal, not an editor. Use open.terminal@\(app.id) to open a folder in it.")
        }
        return app
    }
}
