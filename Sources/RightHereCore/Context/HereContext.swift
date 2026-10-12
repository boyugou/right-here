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

    /// The directory "open here" actions use. It is always checked to be a directory: opening a file
    /// with a terminal app would run it (a `.command` file, for example).
    ///
    /// A single selected folder is opened itself; any other selection opens the folder holding its
    /// first item; with no selection the viewed folder (or the command-line working directory) is
    /// used. A path that is a file yields its folder, and a path that does not exist yields `nil`, so
    /// a mistyped path is not quietly replaced by the folder around it.
    public func workingDirectory(facts: any SystemFacts) -> URL? {
        guard let first = items.first else {
            guard let folder = container ?? (origin == .cli ? facts.currentDirectory : nil) else { return nil }
            return Self.directory(from: folder, facts: facts)
        }
        switch facts.isDirectory(first) {
        case true? where items.count == 1: return first
        case nil: return nil
        default: return Self.directory(from: first.deletingLastPathComponent(), facts: facts)
        }
    }

    /// The first path that was named but does not exist, so a typo can be reported as one.
    public func firstMissingPath(facts: any SystemFacts) -> URL? {
        if let missing = items.first(where: { facts.isDirectory($0) == nil }) { return missing }
        if items.isEmpty, let container, facts.isDirectory(container) == nil { return container }
        return nil
    }

    private static func directory(from url: URL, facts: any SystemFacts) -> URL? {
        switch facts.isDirectory(url) {
        case true?: return url
        case false?: return directory(from: url.deletingLastPathComponent(), facts: facts)
        case nil: return nil
        }
    }

    public var isFolderOnly: Bool { items.isEmpty }
}
