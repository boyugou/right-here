import Foundation

extension HereContext.Origin {
    /// The origin of a request that does not say where it came from: a selection is `items`, a folder alone is
    /// `container`, and neither is the current folder of the command line.
    public static func inferred(hasItems: Bool, hasContainer: Bool) -> HereContext.Origin {
        hasItems ? .items : (hasContainer ? .container : .cli)
    }
}

/// The paths and origin a person or an agent typed, before they are a `HereContext`. The command line and the
/// MCP server both build their context here, so the rules about what a path may be are written once; each
/// surface words the refusals itself.
public struct ContextInput: Sendable, Equatable {
    public enum Resolution: Sendable, Equatable {
        /// Every path must start with `/` (the MCP server: an agent has no meaningful working directory or home).
        case absoluteOnly
        /// A leading `~` is the home folder and a relative path is taken from `directory` (the command line).
        case relative(to: URL)
    }

    public enum Problem: Error, Sendable, Equatable {
        case emptyPath
        case notAbsolute
        case containsNUL
        case unknownOrigin(String)
    }

    public var origin: String?
    public var paths: [String]
    public var container: String?
    public var resolution: Resolution

    public init(origin: String? = nil, paths: [String], container: String? = nil, resolution: Resolution) {
        self.origin = origin
        self.paths = paths
        self.container = container
        self.resolution = resolution
    }

    public func makeContext() throws -> HereContext {
        let items = try paths.map(resolve)
        let folder = try container.map(resolve)
        let chosen: HereContext.Origin
        if let origin {
            guard let parsed = HereContext.Origin(rawValue: origin) else { throw Problem.unknownOrigin(origin) }
            chosen = parsed
        } else {
            chosen = .inferred(hasItems: !items.isEmpty, hasContainer: folder != nil)
        }
        return HereContext(origin: chosen, items: items, container: folder)
    }

    private func resolve(_ path: String) throws -> URL {
        switch resolution {
        case .absoluteOnly:
            // The first scalar, not the first Character: "/" followed by a combining mark is one Character that is not "/".
            guard path.unicodeScalars.first == "/" else { throw Problem.notAbsolute }
        case .relative:
            guard !path.isEmpty else { throw Problem.emptyPath }
        }
        // No real path holds a NUL, and the system calls that check a path stop reading at one, so what is
        // checked would differ from what is later handed to an app.
        guard !path.unicodeScalars.contains("\0") else { throw Problem.containsNUL }
        switch resolution {
        case .absoluteOnly:
            return URL(fileURLWithPath: path)
        case .relative(let directory):
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, relativeTo: directory).lexicallyNormalized
        }
    }
}
