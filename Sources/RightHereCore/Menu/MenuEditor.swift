import Foundation

/// One row of the menu editor: an item of `menu.items` and what it comes to in the Finder menu.
public struct MenuEditorRow: Sendable, Equatable, Identifiable {
    /// The place in `menu.items` (from 1) and the item. The same item may stand in the list more than once (a separator), and a row keeps its identity while the list does.
    public var id: String { "\(position):\(entry)" }
    public var position: Int
    /// The item as `menu.items` writes it: a group (`open-terminal`, `agents`, `copy-path`), an action id (`copy-path.tilde`, `preset.review`) or `-`.
    public var entry: String
    /// The entries of the menu this item makes, as the menu shows them; none when it makes none on this Mac.
    public var nodes: [MenuNode]

    public var isSeparator: Bool { entry == "-" }

    /// What a row says when its item makes nothing here: the group's name, or the item as written.
    public var fallbackTitle: String
}

/// Something the menu does not have yet that can be added to it.
public struct MenuEditorChoice: Sendable, Equatable, Identifiable {
    /// Where the choice is offered from.
    public enum Section: String, Sendable, Equatable, CaseIterable {
        /// A group of the menu itself (the default terminal, the agents, Copy Path).
        case group
        case copyPath, presets, newFile, openApp, agents, reveal
    }

    public var id: String { entry }
    public var entry: String
    public var section: Section
    /// What it would add, as the menu would show it; one entry for an action, a few for a group that makes several.
    public var title: String
    public var icon: Icon?
}

/// The Finder menu as something to edit (ADR 0026): one row for each item of `menu.items`, what can be added, and the changes that a drag, a removal or an addition is.
/// Everything here is a pure function of the config; the window applies the changes it returns through `ConfigService`.
public struct MenuEditorState: Sendable, Equatable {
    public var rows: [MenuEditorRow]
    /// The config does not list the menu: it is the default one, and the first change writes the whole list so that there is one to change.
    public var usesDefaults: Bool
    public var choices: [MenuEditorChoice]
    /// What the file that decides `menu.items` writes for it (`nil`: it does not write the list). Every change is made on condition that the file still says this.
    public var listed: [String]?

    public static let key = "menu.items"

    public init(rows: [MenuEditorRow], usesDefaults: Bool, choices: [MenuEditorChoice], listed: [String]?) {
        self.rows = rows
        self.usesDefaults = usesDefaults
        self.choices = choices
        self.listed = listed
    }

    /// Whether the rows are the items of that file's list one for one. They are not when this Mac turns something off that the list names (`disabled` in its own config): a place among
    /// the rows is then not a place in the list, and nothing is offered to change by place.
    public var isExact: Bool { usesDefaults ? listed == nil : listed == rows.map(\.entry) }
}

public enum MenuEditor {
    /// The groups in the order the menu editor offers them.
    public static let groupOrder = ["open-terminal", "open-editor", "open-with", "agents", "agents-more", "presets", "new-file", "copy-path"]

    /// The editor's state for the menu of the folder `folder`, built by the code the Finder extension runs.
    /// - Parameter inFile: what the file that decides `menu.items` writes for it (`ConfigDocument.elements(of:)`), which the changes are held to.
    public static func state(config: Config, facts: any SystemFacts, localizer: Localizer, folder: URL, inFile: [String]?) -> MenuEditorState {
        let context = HereContext.finder(kind: .container, selected: [], targeted: folder)
        let builder = MenuBuilder(config: config, facts: facts, localizer: localizer)
        let rows = builder.entries(for: context).enumerated().map { index, result in
            MenuEditorRow(position: index + 1, entry: result.entry, nodes: result.nodes, fallbackTitle: title(of: result.entry, localizer: localizer))
        }
        let listed = Set(rows.map(\.entry))
        var choices: [MenuEditorChoice] = []
        for group in groupOrder where !listed.contains(group) {
            let nodes = builder.entries(for: context, items: [group]).first?.nodes ?? []
            // A group that makes several entries is named by all of them, as the menu shows them.
            let shown = nodes.filter { $0.kind != .separator }
            let name = shown.isEmpty ? title(of: group, localizer: localizer) : shown.map(\.title).joined(separator: ", ")
            choices.append(MenuEditorChoice(entry: group, section: .group, title: name, icon: shown.first?.icon ?? MenuBuilder.groupIcon(group)))
        }
        for info in ActionRegistry(config: config, facts: facts, localizer: localizer).catalog() where info.available && !listed.contains(info.id) {
            choices.append(MenuEditorChoice(entry: info.id, section: section(of: info), title: info.title, icon: info.icon))
        }
        return MenuEditorState(rows: rows, usesDefaults: config.menuItems == nil, choices: choices, listed: inFile)
    }

    private static func section(of info: ActionInfo) -> MenuEditorChoice.Section {
        switch info.group {
        case "copy-path": return .copyPath
        case "preset": return .presets
        case "new-file": return .newFile
        case "agent": return .agents
        case "reveal": return .reveal
        // Beside the ways of copying a path, and the page with the ways of opening.
        case "repository": return info.id == ActionRef.copyRepositoryLink.id ? .copyPath : .openApp
        default: return .openApp
        }
    }

    /// What an item is called when it makes nothing here: a group by its name in the menu, anything else as it is written.
    static func title(of entry: String, localizer: Localizer) -> String {
        switch entry {
        case "-": return ""
        case "open-with": return localizer.openWithGroup
        case "agents-more": return localizer.moreAgentsGroup
        case "presets": return localizer.presetsGroup
        case "new-file": return localizer.newFileGroup
        case "copy-path": return localizer.copyPathGroup
        default: return entry
        }
    }

    // MARK: The changes

    /// What every change starts with: the list is still what the window showed, and when the config does not write one the list is made, so that there is a list to change.
    private static func start(_ state: MenuEditorState) -> [ConfigOperation] {
        [.expect(state.listed, in: MenuEditorState.key)] + (state.usesDefaults ? [.set(MenuEditorState.key, .strings(MenuBuilder.defaultItems))] : [])
    }

    /// The changes that do what SwiftUI's `onMove` says: the rows at `source` (counting from 0) go before the row at `destination` (from 0, in the list as it is). The other
    /// rows keep their order, and nothing is written when the rows would stay where they are.
    public static func operations(moving source: IndexSet, to destination: Int, in state: MenuEditorState) -> [ConfigOperation] {
        guard state.isExact else { return [] }
        let moves = ListMoves.operations(moving: source, to: destination, count: state.rows.count, key: MenuEditorState.key)
        return moves.isEmpty ? [] : start(state) + moves
    }

    /// The change that takes the row at `position` (from 1) out of the menu.
    public static func operations(removing position: Int, in state: MenuEditorState) -> [ConfigOperation] {
        guard state.isExact, (1...max(state.rows.count, 1)).contains(position), position <= state.rows.count else { return [] }
        return start(state) + [.remove(at: position, from: MenuEditorState.key)]
    }

    /// The change that puts `entry` (a group, an action id or `-`) in the menu at `position` (from 1; at the end without one).
    public static func operations(adding entry: String, at position: Int? = nil, in state: MenuEditorState) -> [ConfigOperation] {
        guard state.isExact else { return [] }
        if let position, !(1...state.rows.count + 1).contains(position) { return [] }
        return start(state) + [.insert(entry, into: MenuEditorState.key, at: position)]
    }
}
