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

    public init(config: Config, facts: any SystemFacts) {
        self.config = config
        self.facts = facts
    }

    public func info(_ ref: ActionRef) -> ActionInfo {
        var info = ActionInfo(id: ref.id, title: ref.id, shortTitle: ref.id, group: "", icon: nil, available: true, unavailableReason: nil)
        switch ref {
        case .copyPath(let style):
            info.group = "copy-path"
            info.title = "\(Strings.copyPathGroup): \(Strings.copyPath(style))"
            info.shortTitle = Strings.copyPath(style)
            info.icon = .symbol("doc.on.doc")

        case .openTerminal(let id):
            info.group = "open"
            describeApp(&info, terminal: id)

        case .openEditor:
            info.group = "open"
            if let app = try? resolveDefault(role: .editor, configured: config.editor) {
                describeApp(&info, app: app)
            } else {
                unavailable(&info, title: Strings.openIn("Editor"), reason: "No editor is installed.")
            }

        case .openApp(let id):
            info.group = "open"
            if let app = config.app(id: id) {
                describeApp(&info, app: app)
            } else {
                unavailable(&info, title: Strings.openIn(id), reason: "Unknown app \"\(id)\".")
            }

        case .agent(let id, let variantID, let launcher):
            info.group = "agent"
            describeAgent(&info, id: id, variantID: variantID, launcher: launcher)

        case .newFile(let id):
            info.group = "new-file"
            if let template = config.newFile.templates.first(where: { $0.id == id }) {
                info.title = Strings.newFile(template.title)
                info.shortTitle = template.title
                info.icon = .symbol("doc.badge.plus")
            } else {
                unavailable(&info, title: Strings.newFile(id), reason: "Unknown template \"\(id)\".")
            }

        case .reveal:
            info.group = "reveal"
            info.title = Strings.revealInFinder
            info.shortTitle = Strings.revealInFinder
            info.icon = .symbol("magnifyingglass")

        case .user:
            unavailable(&info, title: ref.id, reason: "Custom actions are not available yet.")
        }
        return info
    }

    // MARK: Descriptions

    private func describeApp(_ info: inout ActionInfo, terminal id: String?) {
        let app: AppDescriptor?
        if let id {
            app = config.app(id: id)
        } else {
            app = try? resolveDefault(role: .terminal, configured: config.terminal)
        }
        guard let app else {
            unavailable(&info, title: Strings.openIn(id ?? "Terminal"), reason: id.map { "Unknown terminal \"\($0)\"." } ?? "No terminal is installed.")
            return
        }
        describeApp(&info, app: app)
    }

    private func describeApp(_ info: inout ActionInfo, app: AppDescriptor) {
        info.title = Strings.openIn(app.name)
        info.shortTitle = app.name
        if let bundleID = app.installedBundleID(facts: facts) {
            info.icon = .app(bundleID)
        } else {
            info.available = false
            info.unavailableReason = "\(app.name) is not installed."
        }
    }

    private func describeAgent(_ info: inout ActionInfo, id: String, variantID: String?, launcher: AgentLauncher?) {
        guard let agent = config.agent(id: id) else {
            unavailable(&info, title: Strings.agentHere(id), reason: "Unknown agent \"\(id)\".")
            return
        }
        var variant: AgentDescriptor.Variant?
        if let variantID {
            guard let found = agent.variants.first(where: { $0.id == variantID }) else {
                unavailable(&info, title: Strings.agentHere(agent.name), reason: "\(agent.name) has no variant \"\(variantID)\".")
                return
            }
            variant = found
        }
        info.icon = agent.iconBundleID.flatMap { facts.applicationURL(bundleID: $0) != nil ? Icon.app($0) : nil } ?? .symbol("terminal")

        let chosen = launcher ?? config.agents[id]?.launcher ?? .terminal(nil)
        switch chosen {
        case .desktop:
            info.title = Strings.agentDesktop(agent.name)
            info.shortTitle = info.title
            if agent.desktopLink == nil { unavailable(&info, reason: "\(agent.name) has no desktop app link.") }
            else if let bundleID = agent.iconBundleID, facts.applicationURL(bundleID: bundleID) == nil {
                unavailable(&info, reason: "The \(agent.name) desktop app is not installed.")
            }
        case .terminalLink:
            info.title = Strings.agentLink(agent.name)
            info.shortTitle = info.title
            if agent.terminalLink == nil { unavailable(&info, reason: "\(agent.name) has no terminal link.") }
        case .terminal(let terminalID):
            let terminal: AppDescriptor?
            if let terminalID { terminal = config.app(id: terminalID) } else { terminal = try? resolveDefault(role: .terminal, configured: config.terminal) }
            if let variant {
                info.title = terminalID == nil ? Strings.agentVariant(agent.name, variant.title) : Strings.agentVariantIn(agent.name, variant.title, terminal: terminal?.name ?? terminalID ?? "")
                info.shortTitle = variant.title
            } else {
                info.title = terminalID == nil ? Strings.agentHere(agent.name) : Strings.agentIn(agent.name, terminal: terminal?.name ?? terminalID ?? "")
                info.shortTitle = info.title
            }
            guard let terminal else {
                unavailable(&info, reason: terminalID.map { "Unknown terminal \"\($0)\"." } ?? "No terminal is installed.")
                return
            }
            if terminal.installedBundleID(facts: facts) == nil {
                unavailable(&info, reason: "\(terminal.name) is not installed.")
            } else if !TerminalAdapters.adapter(for: terminal).supportsCommands {
                unavailable(&info, reason: "\(terminal.name) cannot run commands yet.")
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

    func resolveDefault(role: AppDescriptor.Role, configured: String?) throws -> AppDescriptor {
        try Planner(config: config, facts: facts).resolveDefault(role: role, configured: configured)
    }

    // MARK: Catalog

    /// The canonical set of actions on this machine, for `rh actions` and documentation. Terminal
    /// choices for agents are patterns (`agent.<id>@<terminal>`) and are not enumerated.
    public func catalog() -> [ActionInfo] {
        var refs: [ActionRef] = []
        refs += PathStyle.allCases.map { .copyPath($0) }
        refs.append(.openTerminal(nil))
        refs += KnownApps.terminals.map { .openTerminal($0.id) }
        refs += config.apps.filter { $0.role == .terminal }.map { .openTerminal($0.id) }
        refs.append(.openEditor)
        refs += (config.apps + KnownApps.editors).filter { $0.role != .terminal }.map { .openApp($0.id) }
        for agent in (config.customAgents + KnownAgents.all).map({ config.agent(id: $0.id) ?? $0 }) {
            refs.append(.agent(id: agent.id, variant: nil, launcher: nil))
            refs += agent.variants.map { .agent(id: agent.id, variant: $0.id, launcher: nil) }
            if agent.desktopLink != nil { refs.append(.agent(id: agent.id, variant: nil, launcher: .desktop)) }
            if agent.terminalLink != nil { refs.append(.agent(id: agent.id, variant: nil, launcher: .terminalLink)) }
        }
        refs += config.newFile.templates.map { .newFile($0.id) }
        refs.append(.reveal)

        var seen = Set<String>()
        return refs.filter { seen.insert($0.id).inserted }.map(info)
    }
}
