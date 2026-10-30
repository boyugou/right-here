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

    public init(kind: Kind, title: String, icon: Icon?, actionID: String?, children: [MenuNode]) {
        self.kind = kind
        self.title = title
        self.icon = icon
        self.actionID = actionID
        self.children = children
    }

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
    public static let groups: Set<String> = ["open-terminal", "open-editor", "open-with", "agents", "agents-more", "new-file", "copy-path", "presets"]

    private let config: Config
    private let registry: ActionRegistry
    private let defaults: DefaultApps
    private let facts: any SystemFacts
    private let localizer: Localizer

    public init(config: Config, facts: any SystemFacts, localizer: Localizer = .english) {
        self.config = config
        self.facts = facts
        self.localizer = localizer
        self.registry = ActionRegistry(config: config, facts: facts, localizer: localizer)
        self.defaults = DefaultApps(config: config, facts: facts)
    }

    public func build(for context: HereContext) -> [MenuNode] {
        assemble(for: context, collector: nil)
    }

    /// The menu together with what it leaves out and what it changes, as the config asks for them: the default terminal and
    /// editor, the agents, the presets, New File, Copy Path and every entry the config names. It does not list each uninstalled
    /// app of "Open With" or each terminal of "More Agent Options". The menu is the one `build` makes: it is built here, by
    /// the same code, with the notes collected on the way.
    ///
    /// - Parameters:
    ///   - sharedConfig: The config as the shared file alone makes it, when a per-machine overlay is merged over it. `Config`
    ///     does not record which agents the overlay disabled, so they are found as those enabled there and not here.
    ///   - overlayName: The overlay's file name, for the sentence that says so.
    public func explain(for context: HereContext, sharedConfig: Config? = nil, overlayName: String = ConfigLayers.overlayFileName) -> MenuExplanation {
        let collector = MenuNoteCollector(shared: sharedConfig, overlayName: overlayName)
        let menu = assemble(for: context, collector: collector)
        return MenuExplanation(menu: menu, notes: collector.notes)
    }

    /// One entry of `menu.items` and what it comes to in the menu for a context: the entries of the menu that this item makes, none when it makes none here (an
    /// app that is not installed, no agent enabled, presets that need files).
    public struct EntryResult: Sendable, Equatable {
        public var entry: String
        public var nodes: [MenuNode]

        public init(entry: String, nodes: [MenuNode]) {
            self.entry = entry
            self.nodes = nodes
        }
    }

    /// What each item of `menu.items` (the default list without one) comes to, in order and as the menu has them, before separators that stand next to each other are dropped.
    /// The menu is these joined and tidied; the window's menu editor draws one row for each.
    public func entries(for context: HereContext) -> [EntryResult] {
        assembleEntries(for: context, items: config.menuItems ?? Self.defaultItems, collector: nil)
    }

    /// What the items in `items` come to, whether or not the config lists them: what an item that is not in the menu yet would add.
    public func entries(for context: HereContext, items: [String]) -> [EntryResult] {
        assembleEntries(for: context, items: items, collector: nil)
    }

    private func assemble(for context: HereContext, collector: MenuNoteCollector?) -> [MenuNode] {
        let entries = config.menuItems ?? Self.defaultItems
        if entries.isEmpty { collector?.leftOut("Menu", "menu.items lists no entry.") }
        return Self.tidy(assembleEntries(for: context, items: entries, collector: collector).flatMap(\.nodes))
    }

    private func assembleEntries(for context: HereContext, items entries: [String], collector: MenuNoteCollector?) -> [EntryResult] {
        var results: [EntryResult] = []
        // "Open With" leaves out what the menu already offers on its own line.
        var listedAbove = Set<String>()
        if entries.contains("open-terminal"), let terminal = try? defaults.resolve(role: .terminal, configured: config.terminal) { listedAbove.insert(terminal.id) }
        if entries.contains("open-editor"), let editor = try? defaults.resolve(role: .editor, configured: config.editor) { listedAbove.insert(editor.id) }
        for entry in entries {
            var nodes: [MenuNode] = []
            switch entry {
            case "-": nodes.append(.separator)
            case "open-terminal": nodes += defaultApp(.openTerminal(nil), role: .terminal, collector)
            case "open-editor": nodes += defaultApp(.openEditor, role: .editor, collector)
            case "open-with": nodes += openWith(excluding: listedAbove, collector)
            case "agents": nodes += agents(collector)
            case "agents-more":
                // The plain "<Agent> Here" entry is there when `agents` is in the menu, or the agent is named by its own id.
                nodes += moreAgents(context, withPresets: !entries.contains("presets"), collector, hasPlainEntry: { entries.contains("agents") || entries.contains("agent.\($0)") })
            case "presets": nodes += presets(context, collector)
            case "new-file": nodes += newFile(context, collector)
            case "copy-path": nodes += copyPath(collector)
            default:
                // An action named by its id follows the same rules as the groups do for this selection (a preset needs
                // files of the right number), so it is described in the context.
                guard let ref = ActionRef(parsing: entry) else {
                    collector?.leftOut(entry.withControlCharactersEscaped, "it is not a menu group or an action id.")
                    break
                }
                let info = registry.info(ref, context: context)
                if info.available {
                    // Only the entry for the plain path carries the group's name; the other styles keep their own, so that
                    // `copy_path.title` never gives two listed entries one title.
                    if case .copyPath(.absolute) = ref {
                        nodes.append(.action(info, title: config.copyPathTitle ?? localizer.copyPathGroup))
                    } else {
                        nodes.append(.action(info))
                    }
                } else { leftOut(info, ref, collector) }
            }
            results.append(EntryResult(entry: entry, nodes: nodes))
        }
        return results
    }

    // MARK: Groups

    private func single(_ ref: ActionRef, _ collector: MenuNoteCollector? = nil) -> [MenuNode] {
        let info = registry.info(ref)
        if info.available { return [.action(info)] }
        leftOut(info, ref, collector)
        return []
    }

    /// Notes an action the menu is missing and why. An app the per-machine overlay removed is told apart from one that was
    /// never known.
    private func leftOut(_ info: ActionInfo, _ ref: ActionRef, _ collector: MenuNoteCollector?) {
        guard let collector else { return }
        let appID: String?
        switch ref {
        case .openApp(let id): appID = id
        case .openTerminal(let id?): appID = id
        default: appID = nil
        }
        if let appID, config.disabledApps.contains(appID) {
            let name = KnownApps.app(id: appID)?.name ?? appID
            collector.leftOut(localizer.openIn(name), "\(name) is disabled on this Mac by \(collector.overlayName).")
        } else {
            collector.leftOut(info.title, info.unavailableReason)
        }
    }

    /// The entry for the default terminal or editor, and a note when the app the config chose is not the one used.
    private func defaultApp(_ ref: ActionRef, role: AppDescriptor.Role, _ collector: MenuNoteCollector?) -> [MenuNode] {
        let nodes = single(ref, collector)
        if let collector, let node = nodes.first, let found = defaults.substitution(role: role) { collector.changed(node.title, found.sentence) }
        return nodes
    }

    private func agents(_ collector: MenuNoteCollector?) -> [MenuNode] {
        if let collector {
            if config.enabledAgents.isEmpty, collector.shared?.enabledAgents.isEmpty ?? true { collector.leftOut("Agents", "none is enabled; general.agents lists none.") }
            for id in collector.shared?.enabledAgents ?? [] where !config.enabledAgents.contains(id) {
                collector.leftOut(localizer.agentHere(config.agent(id: id)?.name ?? id), "the agent is disabled on this Mac by \(collector.overlayName).")
            }
            if !config.enabledAgents.isEmpty, let found = defaults.substitution(role: .terminal, typing: true) { collector.changed("Agents", found.sentence) }
            for id in config.enabledAgents {
                guard let agent = config.agent(id: id), let flag = config.flagThatSkipsPrompts(for: agent) else { continue }
                collector.changed(localizer.agentHere(agent.name), "it starts \(agent.name) with its permission prompts switched off (\(flag)); presets keep them on.")
            }
        }
        return config.enabledAgents.flatMap { single(.agent(id: $0, variant: nil, launcher: nil), collector) }
    }

    private func openWith(excluding listedAbove: Set<String>, _ collector: MenuNoteCollector?) -> [MenuNode] {
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
        if tidy.isEmpty { collector?.leftOut(localizer.openWithGroup, "no other terminal or editor is installed.") }
        return tidy.isEmpty ? [] : [.submenu(localizer.openWithGroup, icon: Self.groupIcon("open-with"), tidy)]
    }

    /// The "Agent Presets" submenu: the presets whose agent is enabled and that fit this selection. A preset that
    /// needs files is left out of a folder's menu, and the whole submenu when nothing is left.
    private func presets(_ context: HereContext, _ collector: MenuNoteCollector?) -> [MenuNode] {
        var firstRefusal: String?
        let infos = config.presets.compactMap { preset -> (agent: String, info: ActionInfo)? in
            guard let agent = config.agent(for: preset), config.enabledAgents.contains(agent.id) else { return nil }
            let info = registry.info(.preset(id: preset.id, terminal: nil), context: context)
            if !info.available, firstRefusal == nil { firstRefusal = info.unavailableReason }
            return info.available ? (agent.id, info) : nil
        }
        // With several agents in play the agent's name is part of the title; with one it is just noise.
        let oneAgent = Set(infos.map(\.agent)).count <= 1
        let children = infos.map { MenuNode.action($0.info, title: oneAgent ? $0.info.shortTitle : $0.info.title) }
        if children.isEmpty, let firstRefusal { collector?.leftOut(localizer.presetsGroup, firstRefusal) }
        return children.isEmpty ? [] : [.submenu(localizer.presetsGroup, icon: Self.groupIcon("presets"), children)]
    }

    /// What the plain "<Agent> Here" entry does not do: the agent's variants, and its other ways to start. The plain entry
    /// follows the agent's launcher (its desktop app, its terminal link, or a terminal that is the default or the one the
    /// agent names), so that launcher is the one left out here, and the typed launch in the default terminal is offered when
    /// the plain entry is not it.
    private func moreAgents(_ context: HereContext, withPresets: Bool, _ collector: MenuNoteCollector?, hasPlainEntry: (String) -> Bool) -> [MenuNode] {
        var children: [MenuNode] = []
        let defaultTerminal = try? defaults.commandTerminal()
        for id in config.enabledAgents {
            guard let agent = config.agent(id: id) else { continue }
            let plain = hasPlainEntry(id) ? config.launcher(forAgent: id, explicit: nil, hasVariant: false).launcher : nil
            let plainTerminal: String?
            switch plain {
            case .terminal(let named)?: plainTerminal = named ?? defaultTerminal?.id
            default: plainTerminal = nil
            }
            var refs: [ActionRef] = agent.variants.map { .agent(id: id, variant: $0.id, launcher: nil) }
            if agent.desktopLink != nil, plain != .desktop { refs.append(.agent(id: id, variant: nil, launcher: .desktop)) }
            if agent.terminalLink != nil, plain != .terminalLink { refs.append(.agent(id: id, variant: nil, launcher: .terminalLink)) }
            for terminal in config.allApps where terminal.role == .terminal && terminal.id != plainTerminal {
                refs.append(.agent(id: id, variant: nil, launcher: .terminal(terminal.id)))
            }
            let nodes = refs.flatMap { single($0) }
            if !nodes.isEmpty { children += nodes + [.separator] }
        }
        if withPresets { children += presets(context, collector) }
        let tidy = Self.tidy(children)
        return tidy.isEmpty ? [] : [.submenu(localizer.moreAgentsGroup, icon: Self.groupIcon("agents-more"), tidy)]
    }

    private func newFile(_ context: HereContext, _ collector: MenuNoteCollector?) -> [MenuNode] {
        guard context.items.count <= 1 else {
            collector?.leftOut(localizer.newFileGroup, "several items are selected; a new file goes next to one item, or into a folder.")
            return []
        }
        let infos = config.newFile.shownTemplates.map { registry.info(.newFile($0.id)) }.filter(\.available)
        switch infos.count {
        case 0:
            collector?.leftOut(localizer.newFileGroup, config.newFile.templates.isEmpty ? "no template is defined (new_file.template)." : "new_file.hidden leaves out every template.")
            return []
        case 1: return [.action(infos[0])]
        default: return [.submenu(localizer.newFileGroup, icon: Self.groupIcon("new-file"), infos.map { .action($0, title: $0.shortTitle) })]
        }
    }

    private func copyPath(_ collector: MenuNoteCollector?) -> [MenuNode] {
        let infos = config.copyPathStyles.map { registry.info(.copyPath($0)) }
        let groupTitle = config.copyPathTitle ?? localizer.copyPathGroup
        switch infos.count {
        case 0:
            collector?.leftOut(groupTitle, "copy_path.styles lists no style.")
            return []
        case 1:
            let title: String
            if let custom = config.copyPathTitle {
                title = custom
            } else if config.copyPathStyles.first == .absolute {
                title = localizer.copyPathGroup
            } else {
                title = infos[0].title
            }
            return [.action(infos[0], title: title)]
        default: return [.submenu(groupTitle, icon: Self.groupIcon("copy-path"), infos.map { .action($0, title: $0.shortTitle) })]
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

extension MenuBuilder {
    /// The symbol of a group's submenu in the menu, and of the group in the menu editor when it makes nothing for a folder (the presets act on
    /// selected files), so that the editor shows it as the menu does.
    public static func groupIcon(_ group: String) -> Icon? {
        switch group {
        case "open-with": .symbol("arrow.up.forward.app")
        case "presets": .symbol("text.bubble")
        case "agents-more": .symbol("ellipsis.circle")
        case "new-file": .symbol("doc.badge.plus")
        case "copy-path": .symbol("doc.on.doc")
        // Each agent is a line of its own with its own icon; the group of them, when there is none, is a terminal's symbol, as an agent's line is without its app.
        case "agents": .symbol("terminal")
        default: nil
        }
    }
}
