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
        freshness(builtAt: builtAt, now: now, sameConfig: sameConfig) == .fresh
    }

    /// What a menu built earlier is good for.
    public enum Freshness: Equatable, Sendable {
        /// Built from what is installed now, as far as is known: served as it is.
        case fresh
        /// Built from the same config but long enough ago that an app may have come or gone. It is still served, and a new one is built in the background: a right-click
        /// that waits for LaunchServices and the icons of thirty apps is a menu that shows its entries a second late, and an entry for an app that was just
        /// uninstalled does no harm for one click (running it says the app is not there).
        case stale
        /// Built from another config, or from a clock that is not this one's: not served.
        case unusable
    }

    public static func freshness(builtAt: Date, now: Date, sameConfig: Bool) -> Freshness {
        guard sameConfig, now >= builtAt else { return .unusable }
        return now.timeIntervalSince(builtAt) < lifetime ? .fresh : .stale
    }
}
