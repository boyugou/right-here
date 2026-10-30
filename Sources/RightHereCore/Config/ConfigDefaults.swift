import Foundation

/// What a list setting comes to when the config does not write it. An item added to such a list, or taken out of it, is a change of that list: the first change writes it as it is now and
/// then changes it, as the window's editors do, so that `rh config add menu.items presets` leaves the default menu and a preset, and not a menu of one item.
public enum ConfigDefaults {
    /// The list `key` stands for while the config does not write it; `nil` for a list that is empty then (`general.agents`).
    public static func list(for key: String, config: Config) -> [String]? {
        switch key {
        case "menu.items": MenuBuilder.defaultItems
        case "copy_path.styles": Config.defaultCopyPathStyles.map(\.rawValue)
        case "services.items": ActionRegistry.defaultServiceItems(enabledAgents: config.enabledAgents)
        default: nil
        }
    }

    /// The list `key` is as `config` reads it now: what a file writes for it, or else the default. It is what a change of this Mac's own file starts from when only the shared file writes the list: the
    /// first change then keeps the list this Mac shows, and does not replace it with the built-in default.
    public static func shown(for key: String, config: Config) -> [String]? {
        switch key {
        case "menu.items": config.menuItems ?? MenuBuilder.defaultItems
        case "copy_path.styles": config.copyPathStyles.map(\.rawValue)
        case "services.items": config.serviceItems ?? ActionRegistry.defaultServiceItems(enabledAgents: config.enabledAgents)
        default: nil
        }
    }
}
