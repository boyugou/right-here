import Foundation
import RightHereCore

/// What the menu that goes to Finder has to be like for Finder to draw it as the config says. Finder asks the extension for its menu items and draws them itself, so what it
/// does with them is its own: this holds what has been seen of that, each from a report of a real Mac.
public enum FinderMenuPresentation {
    /// Whether Finder draws a separator of an extension's menu as a line. On macOS 26.5.1 it draws an empty row of the height of an entry instead, in the menu and in a
    /// submenu alike (a screenshot of it was reported): `NSMenuItem.separator()` does not come through as a separator. Nobody has seen macOS 27 do that, so
    /// separators stay there; the entries of the menu are the same either way, and only the empty rows are left out.
    public static func showsSeparators(osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> Bool {
        osMajorVersion >= 27
    }

    /// The menu as Finder is to be given it: without its separators when Finder would draw them as empty rows, in submenus too.
    public static func nodes(_ nodes: [MenuNode], separators: Bool) -> [MenuNode] {
        guard !separators else { return nodes }
        return nodes.filter { $0.kind != .separator }.map { node in
            var copy = node
            copy.children = Self.nodes(node.children, separators: false)
            return copy
        }
    }
}
