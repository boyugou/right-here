import Foundation

/// One entry of the Finder context menu, already localized and resolved.
public struct MenuNode: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case action
        case submenu
        case separator
    }

    public var kind: Kind
    public var title: String
    public var icon: Icon?
    public var actionID: String?
    public var children: [MenuNode]

    public static let separator = MenuNode(kind: .separator, title: "", icon: nil, actionID: nil, children: [])

    static func action(_ info: ActionInfo, title: String? = nil) -> MenuNode {
        MenuNode(kind: .action, title: title ?? info.title, icon: info.icon, actionID: info.id, children: [])
    }

    static func submenu(_ title: String, icon: Icon? = nil, _ children: [MenuNode]) -> MenuNode {
        MenuNode(kind: .submenu, title: title, icon: icon, actionID: nil, children: children)
    }

    /// Every action id reachable from this node.
    public var actionIDs: [String] {
        (actionID.map { [$0] } ?? []) + children.flatMap(\.actionIDs)
    }
}

/// Builds the menu for a context from the config. Pure: the result depends only on the inputs.
public struct MenuBuilder: Sendable {
    public static let defaultItems = ["open-terminal", "open-editor", "open-with", "agents", "agents-more", "-", "new-file", "copy-path"]
    public static let groups: Set<String> = ["open-terminal", "open-editor", "open-with", "agents", "agents-more", "new-file", "copy-path"]

    private let config: Config
    private let registry: ActionRegistry
    private let facts: any SystemFacts
    private let localizer: Localizer

    public init(config: Config, facts: any SystemFacts, localizer: Localizer = .english) {
        self.config = config
        self.facts = facts
        self.localizer = localizer
        self.registry = ActionRegistry(config: config, facts: facts, localizer: localizer)
    }

    public func build(for context: HereContext) -> [MenuNode] {
        var nodes: [MenuNode] = []
        let entries = config.menuItems ?? Self.defaultItems
        // "Open With" leaves out what the menu already offers on its own line.
        var listedAbove = Set<String>()
        if entries.contains("open-terminal"), let terminal = try? registry.resolveDefault(role: .terminal, configured: config.terminal) { listedAbove.insert(terminal.id) }
        if entries.contains("open-editor"), let editor = try? registry.resolveDefault(role: .editor, configured: config.editor) { listedAbove.insert(editor.id) }
        for entry in entries {
            switch entry {
            case "-": nodes.append(.separator)
            case "open-terminal": nodes += single(.openTerminal(nil))
            case "open-editor": nodes += single(.openEditor)
            case "open-with": nodes += openWith(excluding: listedAbove)
            case "agents": nodes += config.enabledAgents.flatMap { single(.agent(id: $0, variant: nil, launcher: nil)) }
            case "agents-more": nodes += moreAgents()
            case "new-file": nodes += newFile(context)
            case "copy-path": nodes += copyPath()
            default: nodes += ActionRef(parsing: entry).map(single) ?? []
            }
        }
        return Self.tidy(nodes)
    }

    // MARK: Groups

    private func single(_ ref: ActionRef) -> [MenuNode] {
        let info = registry.info(ref)
        return info.available ? [.action(info)] : []
    }

    private func openWith(excluding listedAbove: Set<String>) -> [MenuNode] {
        let terminals = config.allApps.filter { $0.role == .terminal && !listedAbove.contains($0.id) }
        let others = config.allApps.filter { $0.role != .terminal && !listedAbove.contains($0.id) }
        func entries(_ apps: [AppDescriptor], _ ref: (AppDescriptor) -> ActionRef) -> [MenuNode] {
            var seen = Set<String>()
            return apps.filter { seen.insert($0.id).inserted }.compactMap { app in
                let info = registry.info(ref(app))
                return info.available ? MenuNode.action(info, title: info.shortTitle) : nil
            }
        }
        let children = entries(terminals) { .openTerminal($0.id) } + [.separator] + entries(others) { .openApp($0.id) }
        let tidy = Self.tidy(children)
        return tidy.isEmpty ? [] : [.submenu(localizer.openWithGroup, icon: .symbol("arrow.up.forward.app"), tidy)]
    }

    private func moreAgents() -> [MenuNode] {
        var children: [MenuNode] = []
        let defaultTerminal = try? registry.resolveDefault(role: .terminal, configured: config.terminal)
        for id in config.enabledAgents {
            guard let agent = config.agent(id: id) else { continue }
            var refs: [ActionRef] = agent.variants.map { .agent(id: id, variant: $0.id, launcher: nil) }
            if agent.desktopLink != nil { refs.append(.agent(id: id, variant: nil, launcher: .desktop)) }
            if agent.terminalLink != nil { refs.append(.agent(id: id, variant: nil, launcher: .terminalLink)) }
            for terminal in config.allApps where terminal.role == .terminal && terminal.id != defaultTerminal?.id {
                refs.append(.agent(id: id, variant: nil, launcher: .terminal(terminal.id)))
            }
            let nodes = refs.flatMap(single)
            if !nodes.isEmpty { children += nodes + [.separator] }
        }
        let tidy = Self.tidy(children)
        return tidy.isEmpty ? [] : [.submenu(localizer.moreAgentsGroup, icon: .symbol("ellipsis.circle"), tidy)]
    }

    private func newFile(_ context: HereContext) -> [MenuNode] {
        guard context.items.count <= 1 else { return [] }
        let infos = config.newFile.templates.map { registry.info(.newFile($0.id)) }.filter(\.available)
        switch infos.count {
        case 0: return []
        case 1: return [.action(infos[0])]
        default: return [.submenu(localizer.newFileGroup, icon: .symbol("doc.badge.plus"), infos.map { .action($0, title: $0.shortTitle) })]
        }
    }

    private func copyPath() -> [MenuNode] {
        let infos = config.copyPathStyles.map { registry.info(.copyPath($0)) }
        switch infos.count {
        case 0: return []
        case 1: return [.action(infos[0])]
        default: return [.submenu(localizer.copyPathGroup, icon: .symbol("doc.on.doc"), infos.map { .action($0, title: $0.shortTitle) })]
        }
    }

    /// Drops leading, trailing and repeated separators.
    static func tidy(_ nodes: [MenuNode]) -> [MenuNode] {
        var result: [MenuNode] = []
        for node in nodes {
            if node.kind == .separator, result.last == nil || result.last?.kind == .separator { continue }
            result.append(node)
        }
        while result.last?.kind == .separator { result.removeLast() }
        return result
    }
}
