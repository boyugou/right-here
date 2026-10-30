import Foundation

/// The picture shown next to a menu entry.
public struct Icon: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// The icon of an installed application, identified by bundle identifier.
        case app
        /// An SF Symbol.
        case symbol
        /// The system icon of a kind of file, identified by file name extension (`md`, `txt`).
        case fileType
    }

    public var kind: Kind
    public var value: String

    public static func app(_ bundleID: String) -> Icon { Icon(kind: .app, value: bundleID) }
    public static func symbol(_ name: String) -> Icon { Icon(kind: .symbol, value: name) }
    public static func fileType(_ fileExtension: String) -> Icon { Icon(kind: .fileType, value: fileExtension) }
}
