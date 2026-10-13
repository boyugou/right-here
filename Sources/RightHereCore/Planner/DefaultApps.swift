import Foundation

/// The app an action uses when it does not name one: the default the config sets, else the first installed one in a
/// fixed preference order. The planner, the menu and the registry all ask here, so they cannot disagree about it.
public struct DefaultApps: Sendable {
    public let config: Config
    public let facts: any SystemFacts

    public init(config: Config, facts: any SystemFacts) {
        self.config = config
        self.facts = facts
    }

    /// The configured default as it is, else the first installed app of the role in the preference order.
    public func resolve(role: AppDescriptor.Role, configured: String?) throws(PlanError) -> AppDescriptor {
        if let configured {
            guard let app = config.app(id: configured) else { throw PlanError.unknownApp(configured) }
            // The config can redefine a built-in id with another role; a terminal that is now an editor (or
            // the reverse) is not what the setting asked for, and `rh actions` already says so.
            if role == .terminal, app.role != .terminal { throw PlanError.notATerminal(app) }
            if role == .editor, app.role == .terminal {
                throw PlanError.unsupported("\(app.name) is a terminal, not an editor. Use open.terminal@\(app.id) to open a folder in it.")
            }
            return app
        }
        guard let app = candidates(for: role).first(where: { $0.installedBundleID(facts: facts) != nil }) else {
            throw PlanError.noDefaultApp(role)
        }
        return app
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

    /// The terminal an agent is typed into when none is named: the configured default as it is, else the first
    /// installed one that can run a command. A folder-only terminal (iTerm, kitty and the like) is a fine place to
    /// open a folder but would make every agent entry fail while Terminal.app sits next to it.
    public func commandTerminal() throws(PlanError) -> AppDescriptor {
        if config.terminal != nil { return try resolve(role: .terminal, configured: config.terminal) }
        let capable = candidates(for: .terminal).first { app in
            guard let bundleID = app.installedBundleID(facts: facts) else { return false }
            let adapter = TerminalAdapters.adapter(for: app)
            return adapter.supportsCommands && adapter.commandBlocker(bundleID: bundleID, facts: facts) == nil
        }
        if let capable { return capable }
        return try resolve(role: .terminal, configured: nil)
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
}
