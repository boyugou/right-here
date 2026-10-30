import Foundation

/// A list of text as rows to edit by place (an agent's `args`, the `arguments` of one of its variants, the forms of Copy Path, the Quick Actions), and the changes that edit it (ADR 0026).
///
/// The rows are the items of the list that the file writes for `key`: `listed` is what that file says, and every change is made on condition that it still says it, so that something that changed
/// the file meanwhile is not mistaken for what was shown. When the config reads the list from somewhere else (the other file, a default) `isExact` is `false`, and nothing is changed by place:
/// the page says the list can only be changed as text. A list that has a default (`ConfigDefaults.list`) is the exception: while the file writes none, the rows are the default list, and the first
/// change writes it, as the menu editor does.
public struct ArgumentList: Sendable, Equatable {
    /// The setting that holds the list (`agent.claude.args`, `agent.claude.variant.2.arguments`).
    public var key: String
    /// The arguments, as the config has them.
    public var items: [String]
    /// What the file that decides `key` writes for it (`nil`: nothing).
    public var listed: [String]?
    /// The list the config uses while the file writes none; `nil` for a list that has no default (it is empty then).
    public var defaults: [String]?
    /// The default list as the shared file alone gives it, which is what every other Mac gets; `nil` when it is `defaults`. The default of the Quick Actions depends on the agents of this Mac.
    public var sharedDefaults: [String]?

    public init(key: String, items: [String], listed: [String]?, defaults: [String]? = nil, sharedDefaults: [String]? = nil) {
        self.key = key
        self.items = items
        self.listed = listed
        self.defaults = defaults
        self.sharedDefaults = sharedDefaults
    }

    /// The file the first change goes to, when the default list it writes is not the default of the other Macs: this Mac's own, so that the shared file, which they read, does not take this Mac's
    /// default. `nil` leaves it to the file that decides the setting.
    public var firstChangeTarget: ConfigTarget? {
        usesDefaults && sharedDefaults != nil && sharedDefaults != defaults ? .local : nil
    }

    /// The config's list is the default one because the file writes none.
    public var usesDefaults: Bool { defaults != nil && listed == nil }

    /// Whether the rows are the items of that file's list one for one (or, while it writes none, the default list).
    public var isExact: Bool { usesDefaults ? items == defaults : (listed ?? []) == items }

    /// What every change starts with: the list is still what the page showed, and a default list is written, so that there is a list to change.
    private var guarded: [ConfigOperation] { [.expect(listed, in: key)] + (usesDefaults ? [.set(key, .strings(defaults ?? []))] : []) }

    /// An argument at the end of the list.
    public func adding(_ argument: String) -> [ConfigOperation] {
        let text = argument.trimmingCharacters(in: .whitespaces)
        guard isExact, !text.isEmpty else { return [] }
        return guarded + [.insert(text, into: key, at: nil)]
    }

    /// The argument at `position` (from 1) taken out.
    public func removing(at position: Int) -> [ConfigOperation] {
        guard isExact, position >= 1, position <= items.count else { return [] }
        return guarded + [.remove(at: position, from: key)]
    }

    /// The argument at `position` (from 1) written another way, in its place and with its comments.
    /// - Parameter shown: What the field that asks for this was showing. A list that has changed since (an argument above it was taken out) has another argument at `position` now, and
    ///   that one is not what the person typed over: nothing is changed.
    public func setting(at position: Int, to argument: String, expecting shown: String? = nil) -> [ConfigOperation] {
        let text = argument.trimmingCharacters(in: .whitespaces)
        guard isExact, position >= 1, position <= items.count, !text.isEmpty, items[position - 1] != text, shown.map({ $0 == items[position - 1] }) ?? true else { return [] }
        return guarded + [.replace(at: position, in: key, with: text)]
    }

    /// What a drag in the list says (SwiftUI's `onMove`, counting from 0).
    public func moving(_ source: IndexSet, to destination: Int) -> [ConfigOperation] {
        guard isExact else { return [] }
        let moves = ListMoves.operations(moving: source, to: destination, count: items.count, key: key)
        return moves.isEmpty ? [] : guarded + moves
    }
}
