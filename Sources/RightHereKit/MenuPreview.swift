import Foundation
import RightHereCore

/// One line of the Finder menu as the setup window draws it.
public struct MenuPreviewRow: Sendable, Equatable, Identifiable {
    /// Where the line is in the menu: `2` is the third entry, `2.0` the first entry of that entry's submenu. It is how a
    /// submenu is named in the set of open ones, and it stays the same while the menu does.
    public let id: String
    public let kind: MenuNode.Kind
    /// 0 in the menu itself, one more for each submenu above the line.
    public let level: Int
    public let title: String
    public let icon: Icon?
    /// A submenu with entries in it; only such a line can be opened.
    public let hasChildren: Bool
    public let isExpanded: Bool
}

/// The Finder menu as the setup window previews it, without Finder.
public enum MenuPreview {
    /// The menu the Finder extension shows on the background of the folder `folder`: the same builder, given the
    /// context the extension makes for that click. Nothing when the config has errors. The extension would still show
    /// what is valid in it, but a menu drawn from a broken config tells the person something that is not true, and the
    /// doctor's config check says what is wrong.
    ///
    /// - Parameter separators: Whether Finder draws the separators; when it does not (`FinderMenuPresentation`) the preview leaves them out, as Finder does.
    public static func folderMenu(_ config: ConfigLoadResult, facts: any SystemFacts, folder: URL, localizer: Localizer, separators: Bool = true) -> [MenuNode] {
        guard !config.hasErrors else { return [] }
        let context = HereContext.finder(kind: .container, selected: [], targeted: folder)
        return FinderMenuPresentation.nodes(MenuBuilder(config: config.config, facts: facts, localizer: localizer).build(for: context), separators: separators)
    }

    /// The lines that can be seen: each entry in order, and after a submenu whose id is in `expanded` its own entries,
    /// one level deeper. An entry in a submenu that is shut stays out of sight whatever the set says about it.
    public static func rows(_ nodes: [MenuNode], expanded: Set<String> = []) -> [MenuPreviewRow] {
        var rows: [MenuPreviewRow] = []
        func append(_ nodes: [MenuNode], level: Int, path: [Int]) {
            for (index, node) in nodes.enumerated() {
                let position = path + [index]
                let id = position.map(String.init).joined(separator: ".")
                let hasChildren = node.kind == .submenu && !node.children.isEmpty
                let isExpanded = hasChildren && expanded.contains(id)
                rows.append(MenuPreviewRow(id: id, kind: node.kind, level: level, title: node.title, icon: node.icon, hasChildren: hasChildren, isExpanded: isExpanded))
                if isExpanded { append(node.children, level: level + 1, path: position) }
            }
        }
        append(nodes, level: 0, path: [])
        return rows
    }

    /// The ids of every submenu with entries in it, at any depth: the only lines that can be open. The ids are positions, so
    /// when the menu changes an open submenu keeps its id but may name another entry; `keepingOpen` drops the ones that are gone.
    public static func submenuIDs(_ nodes: [MenuNode]) -> Set<String> {
        var ids = Set<String>()
        func collect(_ nodes: [MenuNode], path: [Int]) {
            for (index, node) in nodes.enumerated() where node.kind == .submenu && !node.children.isEmpty {
                let position = path + [index]
                ids.insert(position.map(String.init).joined(separator: "."))
                collect(node.children, path: position)
            }
        }
        collect(nodes, path: [])
        return ids
    }

    /// The submenus of `open` that the menu still has.
    public static func keepingOpen(_ open: Set<String>, in nodes: [MenuNode]) -> Set<String> {
        open.intersection(submenuIDs(nodes))
    }
}
