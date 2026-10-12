import Foundation
import RightHereCore

/// Menu item tags that always mean the same action.
///
/// Finder hands the extension a copy of the menu it built, and only the tag comes back with a click. The
/// extension builds a menu whenever Finder asks (for items, the window background, the sidebar and the
/// toolbar), so a table that is replaced by each build would send a click on an older menu to whatever
/// stands at that position now. Here the table only grows: an action id keeps its number for as long as the
/// extension runs, and the tag also says which kind of menu listed it, so the click is read against the
/// right selection.
public struct ActionTags: Sendable {
    private var ids: [String] = []
    private var positions: [String: Int] = [:]

    /// Bits of the tag that hold the action's number; the kind of menu is above them.
    static let numberBits = 20

    public init() {}

    /// The tag for `actionID` in a menu of `kind`: the same pair always gives the same tag.
    public mutating func tag(for actionID: String, kind: FinderMenuKind) -> Int {
        let position: Int
        if let known = positions[actionID] {
            position = known
        } else {
            position = ids.count
            ids.append(actionID)
            positions[actionID] = position
        }
        let kindNumber = FinderMenuKind.allCases.firstIndex(of: kind) ?? 0
        return (kindNumber << Self.numberBits) | position
    }

    /// What a tag stands for, or `nil` for a tag this table never handed out.
    public func resolve(_ tag: Int) -> (actionID: String, kind: FinderMenuKind)? {
        guard tag >= 0 else { return nil }
        let kinds = FinderMenuKind.allCases
        let kindNumber = tag >> Self.numberBits
        let position = tag & ((1 << Self.numberBits) - 1)
        guard kinds.indices.contains(kindNumber), ids.indices.contains(position) else { return nil }
        return (ids[position], kinds[kindNumber])
    }
}
