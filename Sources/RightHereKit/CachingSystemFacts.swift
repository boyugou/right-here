import Foundation
import RightHereCore
import Synchronization

/// Wraps another `SystemFacts` and remembers which applications are installed for a short time,
/// so building a menu on every right-click does not repeat LaunchServices lookups.
public final class CachingSystemFacts: SystemFacts, Sendable {
    private let base: any SystemFacts
    private let lifetime: TimeInterval
    private let applications = Mutex<[String: (url: URL?, stored: Date)]>([:])

    public init(base: any SystemFacts = LiveSystemFacts(), lifetime: TimeInterval = 30) {
        self.base = base
        self.lifetime = lifetime
    }

    public var homeDirectory: URL { base.homeDirectory }
    public var currentDirectory: URL { base.currentDirectory }
    public var loginShell: String { base.loginShell }
    public func isDirectory(_ url: URL) -> Bool? { base.isDirectory(url) }
    public func fileExists(_ url: URL) -> Bool { base.fileExists(url) }
    public func itemState(_ url: URL) -> ItemState { base.itemState(url) }
    public func gitRoot(containing url: URL) -> URL? { base.gitRoot(containing: url) }
    public func isRunning(bundleID: String) -> Bool { base.isRunning(bundleID: bundleID) }
    public func displayName(bundleID: String) -> String? { base.displayName(bundleID: bundleID) }
    public func bundleVersion(bundleID: String) -> String? { base.bundleVersion(bundleID: bundleID) }
    public func environment(_ key: String) -> String? { base.environment(key) }
    public func onDiskPath(_ url: URL) -> String { base.onDiskPath(url) }

    public func applicationURL(bundleID: String) -> URL? {
        let now = Date()
        if let cached = applications.withLock({ $0[bundleID] }), now.timeIntervalSince(cached.stored) < lifetime {
            return cached.url
        }
        let url = base.applicationURL(bundleID: bundleID)
        applications.withLock { $0[bundleID] = (url, now) }
        return url
    }
}
