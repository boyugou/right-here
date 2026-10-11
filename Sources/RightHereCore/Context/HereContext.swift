import Foundation

/// What the user pointed at: the selected items, or the folder being viewed.
public struct HereContext: Sendable, Equatable, Codable {
    public enum Origin: String, Sendable, Codable, CaseIterable {
        /// Right-click on one or more selected items.
        case items
        /// Right-click on the empty background of a folder window.
        case container
        case sidebar
        case toolbar
        /// A Quick Action or Service.
        case services
        case cli
    }

    public var origin: Origin
    /// Selected items; standardized absolute file URLs, in the order Finder reported them.
    public var items: [URL]
    /// The folder being viewed or targeted.
    public var container: URL?

    public init(origin: Origin, items: [URL] = [], container: URL? = nil) {
        self.origin = origin
        self.items = items.map(\.lexicallyNormalized)
        self.container = container?.lexicallyNormalized
    }

    /// The items path-oriented actions act on: the selection, or else the folder itself.
    public var pathTargets: [URL] {
        if !items.isEmpty { return items }
        return container.map { [$0] } ?? []
    }

    /// The directory "open here" actions use.
    ///
    /// A single selected folder is opened itself; any other selection opens the folder
    /// holding its first item; with no selection the viewed folder (or the command-line
    /// working directory) is used.
    public func workingDirectory(facts: any SystemFacts) -> URL? {
        guard let first = items.first else {
            return container ?? (origin == .cli ? facts.currentDirectory : nil)
        }
        if items.count == 1, facts.isDirectory(first) == true { return first }
        return first.deletingLastPathComponent()
    }

    public var isFolderOnly: Bool { items.isEmpty }
}
