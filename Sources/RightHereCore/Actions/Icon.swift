import Foundation

/// The picture shown next to a menu entry.
public struct Icon: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// The icon of an installed application, identified by bundle identifier.
        case app
        /// An SF Symbol.
        case symbol
    }

    public var kind: Kind
    public var value: String

    public static func app(_ bundleID: String) -> Icon { Icon(kind: .app, value: bundleID) }
    public static func symbol(_ name: String) -> Icon { Icon(kind: .symbol, value: name) }
}
