import Foundation

/// The Quick Actions (Finder Services, `services.items`) as something to edit in the window (ADR 0026): the actions that Finder lists as Quick Actions, in order, and the actions that can still be
/// added. A pure function of the config and what is installed; the changes it returns are applied through `ConfigService`. The Quick Actions themselves are made from this list by Install or Repair.
public struct QuickActionsState: Sendable, Equatable {
    /// One action that is offered as a Quick Action.
    public struct Row: Sendable, Equatable, Identifiable {
        /// The action id (`open.terminal`, `agent.claude`, `copy-path.absolute`).
        public var id: String
        /// What Finder lists it as; for an id that names no action, the id.
        public var title: String
        public var icon: Icon?
        /// The id names an action that can run on this Mac. One that does not is kept in the list and left out of the Quick Actions.
        public var isAvailable: Bool

        public init(id: String, title: String, icon: Icon?, isAvailable: Bool) {
            self.id = id
            self.title = title
            self.icon = icon
            self.isAvailable = isAvailable
        }
    }

    /// An action that can be added.
    public struct Choice: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var icon: Icon?

        public init(id: String, title: String, icon: Icon?) {
            self.id = id
            self.title = title
            self.icon = icon
        }
    }

    public var rows: [Row]
    /// The actions that exist on this Mac and are not in the list, in the order the registry has them.
    public var choices: [Choice]
    /// The ids as a list to edit (`services.items`); the default list while the config writes none.
    public var list: ArgumentList

    public init(rows: [Row], choices: [Choice], list: ArgumentList) {
        self.rows = rows
        self.choices = choices
        self.list = list
    }
}

public enum QuickActionsOptions {
    public static let key = "services.items"

    /// - Parameters:
    ///   - listed: What the file that decides `services.items` writes for it (`ConfigService.listed`).
    ///   - sharedDefaults: The default list as the shared file alone gives it (the agents it lists), which is what the other Macs have; by default this Mac's.
    public static func state(config: Config, facts: any SystemFacts, localizer: Localizer, listed: [String]?, sharedDefaults: [String]? = nil) -> QuickActionsState {
        let registry = ActionRegistry(config: config, facts: facts, localizer: localizer)
        let defaults = ActionRegistry.defaultServiceItems(enabledAgents: config.enabledAgents)
        let ids = config.serviceItems ?? defaults
        let rows = ids.map { id -> QuickActionsState.Row in
            guard let ref = ActionRef(parsing: id) else { return QuickActionsState.Row(id: id, title: id, icon: nil, isAvailable: false) }
            let info = registry.info(ref)
            return QuickActionsState.Row(id: id, title: info.title, icon: info.icon, isAvailable: info.available)
        }
        let taken = Set(ids)
        let choices = registry.catalog().filter { $0.available && !taken.contains($0.id) }.map { QuickActionsState.Choice(id: $0.id, title: $0.title, icon: $0.icon) }
        return QuickActionsState(rows: rows, choices: choices, list: ArgumentList(key: key, items: ids, listed: listed, defaults: defaults, sharedDefaults: sharedDefaults))
    }

    /// An action put in the list, at the end.
    public static func operations(adding id: String, to state: QuickActionsState) -> [ConfigOperation] {
        state.rows.contains { $0.id == id } ? [] : state.list.adding(id)
    }

    /// The action at `position` (from 1) taken out of the list.
    public static func operations(removingAt position: Int, from state: QuickActionsState) -> [ConfigOperation] {
        state.list.removing(at: position)
    }

    /// What a drag in the list says (SwiftUI's `onMove`, counting from 0).
    public static func operations(moving source: IndexSet, to destination: Int, in state: QuickActionsState) -> [ConfigOperation] {
        state.list.moving(source, to: destination)
    }
}
