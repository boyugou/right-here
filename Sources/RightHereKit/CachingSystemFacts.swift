import Foundation
import RightHereCore
import Synchronization

/// Wraps another `SystemFacts` and remembers which applications are installed for a short time,
/// so building a menu on every right-click does not repeat LaunchServices lookups.
public final class CachingSystemFacts: SystemFacts, Sendable {
    private let base: any SystemFacts
    private let lifetime: TimeInterval
    private let applications = Mutex<[String: (url: URL?, stored: Date)]>([:])
    private let displayNames = Mutex<[String: (name: String?, stored: Date)]>([:])
    private let bundleVersions = Mutex<[String: (version: String?, stored: Date)]>([:])
    private let directories = Mutex<[String: (isDir: Bool?, stored: Date)]>([:])

    public init(base: any SystemFacts = LiveSystemFacts(), lifetime: TimeInterval = 30) {
        self.base = base
        self.lifetime = lifetime
    }

    /// How long what is installed is remembered; the menu cache must live shorter (`MenuCachePolicy`).
    var lifetimeForTesting: TimeInterval { lifetime }

    /// Forgets what is remembered, so that the next lookups ask the system: the menu that is built in the background asks again what is installed.
    public func expire() {
        applications.withLock { $0.removeAll() }
        displayNames.withLock { $0.removeAll() }
        bundleVersions.withLock { $0.removeAll() }
        directories.withLock { $0.removeAll() }
    }

    public var homeDirectory: URL { base.homeDirectory }
    public var currentDirectory: URL { base.currentDirectory }
    public var loginShell: String { base.loginShell }
    /// The folders remembered at most. The key is a path from the Finder and the extension stays loaded for as long as the Mac is on
    /// (ADR 0015), so without a bound the table would grow with every folder the person ever right-clicked.
    static let maxDirectories = 512
    var cachedDirectoryCountForTesting: Int { directories.withLock { $0.count } }

    public func isDirectory(_ url: URL) -> Bool? {
        let key = url.path
        let now = Date()
        let directoryLifetime = min(lifetime, 30)
        if let cached = directories.withLock({ $0[key] }), now.timeIntervalSince(cached.stored) < directoryLifetime {
            return cached.isDir
        }
        let isDir = base.isDirectory(url)
        directories.withLock { cache in
            if cache.count >= Self.maxDirectories {
                cache = cache.filter { now.timeIntervalSince($0.value.stored) < directoryLifetime }
                if cache.count >= Self.maxDirectories { cache.removeAll() }
            }
            cache[key] = (isDir, now)
        }
        return isDir
    }
    public func fileExists(_ url: URL) -> Bool { base.fileExists(url) }
    public func itemState(_ url: URL) -> ItemState { base.itemState(url) }
    public func gitRoot(containing url: URL) -> URL? { base.gitRoot(containing: url) }
    public func isRunning(bundleID: String) -> Bool { base.isRunning(bundleID: bundleID) }
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

    public func displayName(bundleID: String) -> String? {
        let now = Date()
        if let cached = displayNames.withLock({ $0[bundleID] }), now.timeIntervalSince(cached.stored) < lifetime {
            return cached.name
        }
        let name = base.displayName(bundleID: bundleID)
        displayNames.withLock { $0[bundleID] = (name, now) }
        return name
    }

    public func applicationCopies(bundleID: String) -> [AppCopy] { base.applicationCopies(bundleID: bundleID) }

    public func bundleVersion(bundleID: String) -> String? {
        let now = Date()
        if let cached = bundleVersions.withLock({ $0[bundleID] }), now.timeIntervalSince(cached.stored) < lifetime {
            return cached.version
        }
        let version = base.bundleVersion(bundleID: bundleID)
        bundleVersions.withLock { $0[bundleID] = (version, now) }
        return version
    }
}
