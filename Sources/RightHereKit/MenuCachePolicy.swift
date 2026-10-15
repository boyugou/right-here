import Foundation

/// When the Finder extension may hand out a menu it built earlier instead of building one again.
///
/// A menu depends on the config (its files' stamp) and on what is installed on this Mac, which `CachingSystemFacts` remembers for its own
/// lifetime. A menu kept while the config does not change would offer an app that was uninstalled, or leave out one that was just installed,
/// for as long as the extension lives, which is until Finder restarts. So it is kept only briefly: with the facts' lifetime, an installed or
/// removed app shows in the menu within about a minute.
public enum MenuCachePolicy {
    /// Together with the facts' lifetime (30 seconds), at most about a minute.
    public static let lifetime: TimeInterval = 30

    public static func canServe(builtAt: Date, now: Date, sameConfig: Bool) -> Bool {
        sameConfig && now >= builtAt && now.timeIntervalSince(builtAt) < lifetime
    }
}
