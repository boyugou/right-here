import Foundation

/// What is known about one action without running it.
public struct ActionInfo: Sendable, Equatable, Codable {
    public var id: String
    /// Full title for a flat list, for example "Open in Ghostty".
    public var title: String
    /// Title inside the group submenu it belongs to, for example "Full Path".
    public var shortTitle: String
    public var group: String
    public var icon: Icon?
    public var available: Bool
    public var unavailableReason: String?
}

/// Describes actions: titles, icons and whether they can run on this machine.
public struct ActionRegistry: Sendable {
    public let config: Config
    public let facts: any SystemFacts
    public let localizer: Localizer

    private var defaults: DefaultApps { DefaultApps(config: config, facts: facts) }

    public init(config: Config, facts: any SystemFacts, localizer: Localizer = .english) {
        self.config = config
        self.facts = facts
        self.localizer = localizer
    }

    /// The name shown for an app: what the system calls it in the person's language when the menu
    /// is localized, otherwise the catalog name.
    private func name(of app: AppDescriptor) -> String {
        guard localizer.resolvedLanguage != "en", let bundleID = app.installedBundleID(facts: facts) else { return app.name }
        return facts.displayName(bundleID: bundleID) ?? app.name
    }

    public func info(_ ref: ActionRef) -> ActionInfo {
        var info = ActionInfo(id: ref.id, title: ref.id, shortTitle: ref.id, group: "", icon: nil, available: true, unavailableReason: nil)
        switch ref {
        case .copyPath(let style):
            info.group = "copy-path"
            info.title = localizer.copyPathTitle(style)
            info.shortTitle = localizer.copyPath(style)
            info.icon = .symbol("doc.on.doc")

        case .openTerminal(let id):
            info.group = "open"
            describeApp(&info, terminal: id)

        case .openEditor:
            info.group = "open"
            switch defaultApp(.editor, configured: config.editor) {
            case .success(let app): describeApp(&info, app: app)
            case .failure(let error): unavailable(&info, title: localizer.openIn("Editor"), reason: error.message)
            }

        case .openApp(let id):
            info.group = "open"
            if let app = config.app(id: id) {
                describeApp(&info, app: app)
            } else {
                unavailable(&info, title: localizer.openIn(id), reason: "Unknown app \"\(id)\".")
            }

        case .agent(let id, let variantID, let launcher):
            info.group = "agent"
            describeAgent(&info, id: id, variantID: variantID, launcher: launcher)

        case .preset(let id, let terminal):
            info.group = "preset"
            describePreset(&info, id: id, terminal: terminal)

        case .newFile(let id):
            info.group = "new-file"
            if let template = config.newFile.templates.first(where: { $0.id == id }) {
                info.title = template.localizedNewTitle(localizer)
                info.shortTitle = template.localizedTitle(localizer)
                info.icon = .symbol("doc.badge.plus")
            } else {
                unavailable(&info, title: localizer.newFile(id), reason: "Unknown template \"\(id)\".")
            }

        case .reveal:
            info.group = "reveal"
            info.title = localizer.revealInFinder
            info.shortTitle = localizer.revealInFinder
            info.icon = .symbol("magnifyingglass")

        case .user:
            unavailable(&info, title: ref.id, reason: "Custom actions are not available yet.")
        }
        return info
    }

    /// `info` for an action about to be offered in a menu: a preset also needs something to run on and, when its prompt
    /// names files, a selection of the right size. This counts the selected items and never looks at them (building a
    /// menu does no file system work); whether they are files and not folders is left to the planner in `rh`.
    public func info(_ ref: ActionRef, context: HereContext) -> ActionInfo {
        var info = info(ref)
        guard info.available, case .preset(let id, _) = ref, let preset = config.preset(id: id) else { return info }
        if context.items.isEmpty, context.container == nil, context.origin != .cli {
            unavailable(&info, reason: "There is no folder to run in.")
        } else if let refusal = preset.refusal(forFileCount: context.items.count) {
            unavailable(&info, reason: refusal)
        }
        return info
    }

    // MARK: Descriptions

    private func describePreset(_ info: inout ActionInfo, id: String, terminal terminalID: String?) {
        guard let preset = config.preset(id: id) else {
            unavailable(&info, title: id, reason: "Unknown preset \"\(id)\".")
            return
        }
        let presetTitle = preset.localizedTitle(localizer)
        info.title = presetTitle
        info.shortTitle = presetTitle
        if let refusal = config.presetAgentRefusal(preset) {
            unavailable(&info, reason: refusal)
            return
        }
        guard let agent = config.agent(for: preset) else { return }
        info.title = localizer.agentVariant(agent.name, presetTitle)
        info.icon = agent.iconBundleID.flatMap { facts.applicationURL(bundleID: $0) != nil ? Icon.app($0) : nil } ?? .symbol("terminal")
        let resolved = config.launcher(forAgent: agent.id, explicit: terminalID.map { .terminal($0) }, hasVariant: true)
        guard case .terminal(let chosen) = resolved.launcher else { return }
        if let blocker = commandTerminalBlocker(chosen) { unavailable(&info, reason: blocker) }
    }

    /// Why a command cannot be typed into the terminal (the named one, or the default for commands), or `nil`.
    private func commandTerminalBlocker(_ terminalID: String?) -> String? {
        let terminal: AppDescriptor?
        if let terminalID { terminal = config.app(id: terminalID).flatMap { $0.role == .terminal ? $0 : nil } } else { terminal = try? defaults.commandTerminal() }
        guard let terminal else { return terminalID.map { "Unknown terminal \"\($0)\"." } ?? "No terminal is installed." }
        guard let bundleID = terminal.installedBundleID(facts: facts) else { return "\(terminal.name) is not installed." }
        let adapter = TerminalAdapters.adapter(for: terminal)
        if !adapter.supportsCommands { return "\(terminal.name) cannot run commands yet." }
        return adapter.commandBlocker(bundleID: bundleID, facts: facts)
    }

    private func describeApp(_ info: inout ActionInfo, terminal id: String?) {
        let app: AppDescriptor
        if let id {
            guard let found = config.app(id: id) else {
                unavailable(&info, title: localizer.openIn(id), reason: PlanError.unknownTerminal(id).message)
                return
            }
            app = found
        } else {
            switch defaultApp(.terminal, configured: config.terminal) {
            case .success(let found): app = found
            case .failure(let error):
                unavailable(&info, title: localizer.openIn("Terminal"), reason: error.message)
                return
            }
        }
        describeApp(&info, app: app)
        if info.available, app.role != .terminal {
            unavailable(&info, reason: "\(app.name) is not a terminal. Use open.app.\(app.id) to open files with it.")
        }
    }

    private func describeApp(_ info: inout ActionInfo, app: AppDescriptor) {
        info.title = localizer.openIn(name(of: app))
        info.shortTitle = name(of: app)
        if let bundleID = app.installedBundleID(facts: facts) {
            info.icon = .app(bundleID)
        } else {
            info.available = false
            info.unavailableReason = "\(app.name) is not installed."
        }
    }

    private func describeAgent(_ info: inout ActionInfo, id: String, variantID: String?, launcher: AgentLauncher?) {
        guard let agent = config.agent(id: id) else {
            unavailable(&info, title: localizer.agentHere(id), reason: "Unknown agent \"\(id)\".")
            return
        }
        var variant: AgentDescriptor.Variant?
        if let variantID {
            guard let found = agent.variants.first(where: { $0.id == variantID }) else {
                unavailable(&info, title: localizer.agentHere(agent.name), reason: "\(agent.name) has no variant \"\(variantID)\".")
                return
            }
            variant = found
        }
        info.icon = agent.iconBundleID.flatMap { facts.applicationURL(bundleID: $0) != nil ? Icon.app($0) : nil } ?? .symbol("terminal")

        let resolved = config.launcher(forAgent: id, explicit: launcher, hasVariant: variant != nil)
        if let conflict = resolved.conflict {
            info.title = localizer.agentVariant(agent.name, variant?.localizedTitle(localizer) ?? "")
            info.shortTitle = variant?.localizedTitle(localizer) ?? info.title
            unavailable(&info, reason: conflict)
            return
        }
        switch resolved.launcher {
        case .desktop:
            info.title = localizer.agentDesktop(agent.name)
            info.shortTitle = info.title
            if agent.desktopLink == nil { unavailable(&info, reason: "\(agent.name) has no desktop app link.") }
            else if let bundleID = agent.iconBundleID, facts.applicationURL(bundleID: bundleID) == nil {
                unavailable(&info, reason: "The \(agent.name) desktop app is not installed.")
            }
        case .terminalLink:
            info.title = localizer.agentLink(agent.name)
            info.shortTitle = info.title
            if agent.terminalLink == nil { unavailable(&info, reason: "\(agent.name) has no terminal link.") }
        case .terminal(let terminalID):
            let terminal: AppDescriptor?
            if let terminalID { terminal = config.app(id: terminalID).flatMap { $0.role == .terminal ? $0 : nil } } else { terminal = try? defaults.commandTerminal() }
            let terminalName = terminal.map(name(of:)) ?? terminalID ?? ""
            if let variant {
                let variantTitle = variant.localizedTitle(localizer)
                info.title = terminalID == nil ? localizer.agentVariant(agent.name, variantTitle) : localizer.agentVariantIn(agent.name, variantTitle, terminal: terminalName)
                info.shortTitle = variantTitle
            } else {
                info.title = terminalID == nil ? localizer.agentHere(agent.name) : localizer.agentIn(agent.name, terminal: terminalName)
                info.shortTitle = info.title
            }
            guard let terminal else {
                unavailable(&info, reason: terminalID.map { "Unknown terminal \"\($0)\"." } ?? "No terminal is installed.")
                return
            }
            if let bundleID = terminal.installedBundleID(facts: facts) {
                let adapter = TerminalAdapters.adapter(for: terminal)
                if !adapter.supportsCommands {
                    unavailable(&info, reason: "\(terminal.name) cannot run commands yet.")
                } else if let blocker = adapter.commandBlocker(bundleID: bundleID, facts: facts) {
                    unavailable(&info, reason: blocker)
                }
            } else {
                unavailable(&info, reason: "\(terminal.name) is not installed.")
            }
        }
    }

    private func unavailable(_ info: inout ActionInfo, title: String? = nil, reason: String) {
        if let title {
            info.title = title
            info.shortTitle = title
        }
        info.available = false
        info.unavailableReason = reason
    }

    // MARK: Defaults

    private func defaultApp(_ role: AppDescriptor.Role, configured: String?) -> Result<AppDescriptor, PlanError> {
        do throws(PlanError) { return .success(try defaults.resolve(role: role, configured: configured)) } catch { return .failure(error) }
    }

    // MARK: Catalog

    /// The canonical set of actions on this machine, for `rh actions` and documentation. Terminal
    /// choices for agents are patterns (`agent.<id>@<terminal>`) and are not enumerated.
    /// The catalog id closest to a mistyped one ("copy-path.absolut"), if any is near.
    public func closestID(to word: String) -> String? {
        Suggestion.closest(to: word, in: catalog().map(\.id))
    }

    /// Reads an action id typed by a person or an agent. A word that is not an id comes back as an error that
    /// names the closest real id, so every surface says it the same way.
    public func resolve(_ id: String) throws -> ActionRef {
        guard let ref = ActionRef(parsing: id) else { throw UnknownActionID(id: id, suggestion: closestID(to: id)) }
        return ref
    }

    public func catalog() -> [ActionInfo] {
        var refs: [ActionRef] = []
        refs += PathStyle.allCases.map { .copyPath($0) }
        refs.append(.openTerminal(nil))
        refs += config.allApps.filter { $0.role == .terminal }.map { .openTerminal($0.id) }
        refs.append(.openEditor)
        refs += config.allApps.filter { $0.role != .terminal }.map { .openApp($0.id) }
        for agent in (config.customAgents + KnownAgents.all).map({ config.agent(id: $0.id) ?? $0 }) {
            refs.append(.agent(id: agent.id, variant: nil, launcher: nil))
            refs += agent.variants.map { .agent(id: agent.id, variant: $0.id, launcher: nil) }
            if agent.desktopLink != nil { refs.append(.agent(id: agent.id, variant: nil, launcher: .desktop)) }
            if agent.terminalLink != nil { refs.append(.agent(id: agent.id, variant: nil, launcher: .terminalLink)) }
        }
        refs += config.presets.map { .preset(id: $0.id, terminal: nil) }
        refs += config.newFile.templates.map { .newFile($0.id) }
        refs.append(.reveal)

        var seen = Set<String>()
        return refs.filter { seen.insert($0.id).inserted }.map(info)
    }
}
